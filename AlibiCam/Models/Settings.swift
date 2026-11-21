import Foundation
import Combine

/// 视频画质档位（对应原项目 Quality）
enum VideoQuality: String, CaseIterable, Identifiable {
    case FHD = "FHD"
    case HD720 = "720p"
    case HD1080 = "1080p"
    case UHD4K = "4K"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .FHD: return "1080p (FHD)"
        case .HD720: return "720p"
        case .HD1080: return "1080p"
        case .UHD4K: return "4K"
        }
    }

    var width: Int32 {
        switch self {
        case .HD720: return 1280
        case .FHD, .HD1080: return 1920
        case .UHD4K: return 3840
        }
    }

    var height: Int32 {
        switch self {
        case .HD720: return 720
        case .FHD, .HD1080: return 1080
        case .UHD4K: return 2160
        }
    }
}

enum AutoStopSensitivity: String, CaseIterable, Identifiable {
    case relaxed, standard, sensitive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .relaxed: return "宽松"
        case .standard: return "标准"
        case .sensitive: return "灵敏"
        }
    }
    /// 触发自动停止的加速度阈值（g 单位）
    var threshold: Double {
        switch self {
        case .relaxed: return 1.8
        case .standard: return 1.35
        case .sensitive: return 1.1
        }
    }
}

enum CameraPosition: String, CaseIterable, Identifiable {
    case back, front
    var id: String { rawValue }
    var label: String { self == .back ? "后置" : "前置" }
}

/// 用 UserDefaults 持久化设置，对齐原项目 AppSettings 的核心字段
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var maxDurationMinutes: Int {
        didSet { defaults.set(maxDurationMinutes, forKey: Key.maxDuration) }
    }
    @Published var intervalMinutes: Int {
        didSet { defaults.set(intervalMinutes, forKey: Key.interval) }
    }
    @Published var quality: VideoQuality {
        didSet { defaults.set(quality.rawValue, forKey: Key.quality) }
    }
    @Published var frameRate: Int {
        didSet { defaults.set(frameRate, forKey: Key.fps) }
    }
    @Published var bitRateMbps: Int {
        didSet { defaults.set(bitRateMbps, forKey: Key.bitrate) }
    }
    @Published var cameraPosition: CameraPosition {
        didSet { defaults.set(cameraPosition.rawValue, forKey: Key.camera) }
    }
    @Published var autoStopEnabled: Bool {
        didSet { defaults.set(autoStopEnabled, forKey: Key.autoStop) }
    }
    @Published var autoStopSensitivity: AutoStopSensitivity {
        didSet { defaults.set(autoStopSensitivity.rawValue, forKey: Key.autoStopSens) }
    }
    @Published var permanentlyDelete: Bool {
        didSet { defaults.set(permanentlyDelete, forKey: Key.permaDelete) }
    }
    @Published var recordAudio: Bool {
        didSet { defaults.set(recordAudio, forKey: Key.audio) }
    }
    @Published var stabilizationEnabled: Bool {
        didSet { defaults.set(stabilizationEnabled, forKey: Key.stabilization) }
    }

    private enum Key {
        static let maxDuration = "maxDurationMinutes"
        static let interval = "intervalMinutes"
        static let quality = "quality"
        static let fps = "frameRate"
        static let bitrate = "bitRateMbps"
        static let camera = "cameraPosition"
        static let autoStop = "autoStopEnabled"
        static let autoStopSens = "autoStopSensitivity"
        static let permaDelete = "permanentlyDelete"
        static let audio = "recordAudio"
        static let stabilization = "stabilizationEnabled"
    }

    init() {
        self.maxDurationMinutes = defaults.object(forKey: Key.maxDuration) as? Int ?? 30
        self.intervalMinutes = defaults.object(forKey: Key.interval) as? Int ?? 5
        let q = defaults.string(forKey: Key.quality) ?? ""
        self.quality = VideoQuality(rawValue: q) ?? .FHD
        self.frameRate = defaults.object(forKey: Key.fps) as? Int ?? 24
        self.bitRateMbps = defaults.object(forKey: Key.bitrate) as? Int ?? 2
        let c = defaults.string(forKey: Key.camera) ?? ""
        self.cameraPosition = CameraPosition(rawValue: c) ?? .back
        self.autoStopEnabled = defaults.object(forKey: Key.autoStop) as? Bool ?? false
        let s = defaults.string(forKey: Key.autoStopSens) ?? ""
        self.autoStopSensitivity = AutoStopSensitivity(rawValue: s) ?? .standard
        self.permanentlyDelete = defaults.object(forKey: Key.permaDelete) as? Bool ?? true
        self.recordAudio = defaults.object(forKey: Key.audio) as? Bool ?? true
        self.stabilizationEnabled = defaults.object(forKey: Key.stabilization) as? Bool ?? false
    }

    var maxDurationSeconds: TimeInterval { TimeInterval(maxDurationMinutes) * 60 }
    var intervalSeconds: TimeInterval { TimeInterval(intervalMinutes) * 60 }
}
