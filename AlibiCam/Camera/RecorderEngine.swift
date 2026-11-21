import Foundation
import Combine
import AVFoundation
import CoreMotion
import UIKit

enum RecorderError: Error, LocalizedError {
    case noCamera
    case permissionDenied
    case setupFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCamera: return "未找到可用摄像头"
        case .permissionDenied: return "相机或麦克风权限被拒绝，请在系统设置中开启"
        case .setupFailed(let m): return "初始化失败：\(m)"
        case .writeFailed(let m): return "写入失败：\(m)"
        }
    }
}

/// 核心录像引擎：连续采集 → 定时分段写盘 → 滚动删除旧片段
/// 实现对应原项目 IntervalRecorderService + VideoRecorderService 的核心循环
final class RecorderEngine: NSObject, ObservableObject {

    // MARK: - 状态
    enum State: String {
        case idle, preparing, recording, paused, error
    }

    /// 供 SwiftUI 相机预览使用
    var previewSession: AVCaptureSession { session }

    @Published var state: State = .idle
    @Published var errorMessage: String?
    @Published var currentSegmentIndex: Int64 = 0
    @Published var segmentCount: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var autoStopped: Bool = false

    var onAutoStop: (() -> Void)?

    // MARK: - 采集
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.leo.alibi.cam.session", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "app.leo.alibi.cam.writer", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    // MARK: - 写入
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var writerStartTime: CMTime?
    private var isWriting = false
    private var currentURL: URL?

    // MARK: - 计时
    private var cycleTimer: DispatchSourceTimer?
    private var elapsedTimer: DispatchSourceTimer?
    private var segmentStartWallDate = Date()
    private var totalStartWallDate = Date()

    // MARK: - 姿态
    private let motionManager = CMMotionManager()
    private var lastAutoStopCheck = Date()

    // MARK: - 保活（后台音频）
    private var silencePlayer: AVAudioPlayer?

    private let settings: Settings
    private let store = SegmentStore.shared

    init(settings: Settings) {
        self.settings = settings
        super.init()
    }

    // MARK: - 权限
    static func checkPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            var granted = false
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { g in
                granted = g
                sem.signal()
            }
            sem.wait()
            return granted
        default: return false
        }
    }

    // MARK: - 启动
    func start() {
        guard RecorderEngine.checkPermission() else {
            let msg = RecorderError.permissionDenied.localizedDescription
            DispatchQueue.main.async { self.state = .error; self.errorMessage = msg }
            return
        }
        DispatchQueue.main.async { self.state = .preparing; self.errorMessage = nil; self.autoStopped = false }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.setupSession()
                self.store.prepare()
                self.store.clearAll(permanently: self.settings.permanentlyDelete)
                self.startSilence()
                self.session.startRunning()
                self.writerQueue.async { self.beginSegment() }

                DispatchQueue.main.async {
                    self.state = .recording
                    self.totalStartWallDate = Date()
                }
            } catch {
                let msg = (error as? RecorderError)?.localizedDescription ?? error.localizedDescription
                DispatchQueue.main.async { self.state = .error; self.errorMessage = msg }
            }
        }
    }

    private func setupSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        // 摄像头
        let pos: AVCaptureDevice.Position = settings.cameraPosition == .back ? .back : .front
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
                ?? AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw RecorderError.noCamera
        }
        do {
            videoInput = try AVCaptureDeviceInput(device: camera)
            if let vi = videoInput, session.canAddInput(vi) { session.addInput(vi) }
        } catch {
            session.commitConfiguration()
            throw RecorderError.setupFailed(error.localizedDescription)
        }

        // 帧率锁定
        do {
            try camera.lockForConfiguration()
            let frameDur = CMTime(value: 1, timescale: Int32(settings.frameRate))
            camera.activeVideoMinFrameDuration = frameDur
            camera.activeVideoMaxFrameDuration = frameDur
            camera.unlockForConfiguration()
        } catch { /* 帧率锁定失败不致命 */ }

        // 视频输出
        videoOutput.setSampleBufferDelegate(self, queue: writerQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = (pos == .front)
            }
            if settings.stabilizationEnabled && conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .standard
            }
        }

        // 音频
        if settings.recordAudio {
            if let mic = AVCaptureDevice.default(for: .audio),
               let ai = try? AVCaptureDeviceInput(device: mic), session.canAddInput(ai) {
                session.addInput(ai)
                audioInput = ai
                audioOutput.setSampleBufferDelegate(self, queue: writerQueue)
                if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
            }
        }

        session.commitConfiguration()
    }

    // MARK: - 分段写入
    private func beginSegment() {
        let url = store.nextSegmentURL()
        currentURL = url
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            fail("创建写入器失败：\(error.localizedDescription)")
            return
        }

        let w = settings.quality.width
        let h = settings.quality.height
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitRateMbps * 1_000_000,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate
            ] as [String: Any]
        ]
        let vin = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vin.expectsMediaDataInRealTime = true
        if writer.canAdd(vin) { writer.add(vin) }

        var ain: AVAssetWriterInput?
        if settings.recordAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); ain = a }
        }

        guard writer.startWriting() else {
            fail("启动写入失败：\(writer.error?.localizedDescription ?? "")")
            return
        }

        assetWriter = writer
        videoWriterInput = vin
        audioWriterInput = ain
        writerStartTime = nil
        isWriting = true
        segmentStartWallDate = Date()

        DispatchQueue.main.async {
            self.currentSegmentIndex = self.store.counter
            self.segmentCount = self.store.currentSegments().count
        }
    }

    private func endSegment() {
        guard isWriting, let writer = assetWriter else { return }
        isWriting = false
        let vin = videoWriterInput
        let ain = audioWriterInput
        videoWriterInput = nil
        audioWriterInput = nil
        assetWriter = nil

        writerQueue.async { [weak self] in
            vin?.markAsFinished()
            ain?.markAsFinished()
            writer.finishWriting {
                guard let self = self else { return }
                self.store.prune(
                    keepRecentSeconds: self.settings.maxDurationSeconds,
                    permanently: self.settings.permanentlyDelete
                )
                DispatchQueue.main.async {
                    self.segmentCount = self.store.currentSegments().count
                }
                self.beginSegment()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopTimers()
            self.stopMotion()
            self.stopSilence()
            self.session.stopRunning()

            if self.isWriting, let writer = self.assetWriter {
                self.isWriting = false
                let vin = self.videoWriterInput
                let ain = self.audioWriterInput
                self.videoWriterInput = nil
                self.audioWriterInput = nil
                self.assetWriter = nil
                vin?.markAsFinished()
                ain?.markAsFinished()
                writer.finishWriting {
                    self.store.prune(
                        keepRecentSeconds: self.settings.maxDurationSeconds,
                        permanently: self.settings.permanentlyDelete
                    )
                    DispatchQueue.main.async { self.state = .idle }
                }
            } else {
                DispatchQueue.main.async { self.state = .idle }
            }
        }
    }

    private func fail(_ msg: String) {
        DispatchQueue.main.async { self.state = .error; self.errorMessage = msg }
    }

    // MARK: - 定时器
    func startTimers() {
        stopTimers()
        let cycle = DispatchSource.makeTimerSource(queue: sessionQueue)
        cycle.schedule(deadline: .now() + settings.intervalSeconds,
                       repeating: settings.intervalSeconds)
        cycle.setEventHandler { [weak self] in
            guard let self = self, self.state == .recording else { return }
            self.endSegment()
        }
        cycle.resume()
        cycleTimer = cycle

        let elapsed = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        elapsed.schedule(deadline: .now(), repeating: 1.0)
        elapsed.setEventHandler { [weak self] in
            guard let self = self, self.state == .recording else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(self.totalStartWallDate))
        }
        elapsed.resume()
        elapsedTimer = elapsed
    }

    func stopTimers() {
        cycleTimer?.cancel(); cycleTimer = nil
        elapsedTimer?.cancel(); elapsedTimer = nil
    }

    func startMotion() {
        guard settings.autoStopEnabled, motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.2
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let a = data?.acceleration, self.state == .recording else { return }
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let threshold = self.settings.autoStopSensitivity.threshold
            if magnitude > threshold {
                self.triggerAutoStop()
            }
        }
    }

    func stopMotion() {
        motionManager.stopAccelerometerUpdates()
    }

    private func triggerAutoStop() {
        DispatchQueue.main.async {
            self.autoStopped = true
        }
        onAutoStop?()
        stop()
    }

    // MARK: - 后台保活：播放静音音频
    private func startSilence() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        do {
            silencePlayer = try AVAudioPlayer(contentsOf: url)
            silencePlayer?.numberOfLoops = -1
            silencePlayer?.volume = 0.0
            silencePlayer?.prepareToPlay()
            silencePlayer?.play()
        } catch { /* 保活失败不影响前台录制 */ }
    }

    private func stopSilence() {
        silencePlayer?.stop()
        silencePlayer = nil
    }
}

// MARK: - SampleBuffer 代理
extension RecorderEngine: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isWriting,
              let writer = assetWriter,
              writer.status == .writing else { return }

        let isVideo = output is AVCaptureVideoDataOutput
        let input = isVideo ? videoWriterInput : audioWriterInput
        guard let input = input, input.isReadyForMoreMediaData else { return }

        if writerStartTime == nil {
            writerStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: writerStartTime!)
        }

        if !input.append(sampleBuffer) {
            if let err = writer.error {
                fail(err.localizedDescription)
            }
        }
    }
}
