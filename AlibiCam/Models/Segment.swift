import Foundation
import AVFoundation
import CoreMedia

/// 一个录像分段（对应原项目 BatchesFolder 里的一个批次文件）
struct Segment: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let index: Int64
    let startDate: Date

    var durationText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: startDate)
    }

    var sizeText: String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return "—"
        }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

/// 管理分段文件的存储目录、滚动删除、保存导出
final class SegmentStore {
    static let shared = SegmentStore()

    private let fm = FileManager.default
    private var baseDir: URL {
        let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AlibiSegments", isDirectory: true)
    }
    private var savedDir: URL {
        baseDir.appendingPathComponent("Saved", isDirectory: true)
    }

    private var counterFile: URL { baseDir.appendingPathComponent("counter.txt") }
    private(set) var counter: Int64 = 0

    private init() {
        prepare()
    }

    func prepare() {
        if !fm.fileExists(atPath: baseDir.path) {
            try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: savedDir.path) {
            try? fm.createDirectory(at: savedDir, withIntermediateDirectories: true)
        }
        if let s = try? String(contentsOf: counterFile, encoding: .utf8),
           let v = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            counter = v
        }
    }

    func nextSegmentURL() -> URL {
        counter += 1
        try? String(counter).write(to: counterFile, atomically: true, encoding: .utf8)
        let name = String(format: "seg_%012d.mp4", counter)
        return baseDir.appendingPathComponent(name)
    }

    /// 返回当前所有分段（按序号升序）
    func currentSegments() -> [Segment] {
        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        var result: [Segment] = []
        for url in files where url.lastPathComponent.hasPrefix("seg_") && url.pathExtension == "mp4" {
            let name = url.deletingPathExtension().lastPathComponent
            let idxStr = name.replacingOccurrences(of: "seg_", with: "")
            let idx = Int64(idxStr) ?? 0
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            result.append(Segment(url: url, index: idx, startDate: created))
        }
        return result.sorted { $0.index < $1.index }
    }

    /// 滚动删除：只保留最近 maxDurationSeconds 内的分段
    @discardableResult
    func prune(keepRecentSeconds: TimeInterval, permanently: Bool) -> Int {
        let segs = currentSegments()
        guard segs.count > 1 else { return 0 }
        let now = Date()
        var deleted = 0
        for seg in segs {
            if now.timeIntervalSince(seg.startDate) > keepRecentSeconds {
                delete(segment: seg, permanently: permanently)
                deleted += 1
            }
        }
        return deleted
    }

    private func delete(segment: Segment, permanently: Bool) {
        guard fm.fileExists(atPath: segment.url.path) else { return }
        if permanently {
            try? fm.removeItem(at: segment.url)
        } else {
            // iOS 没有回收站概念，直接删到 App 的 Trash 目录保留
            let trash = baseDir.appendingPathComponent("Trash", isDirectory: true)
            if !fm.fileExists(atPath: trash.path) {
                try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
            }
            try? fm.moveItem(at: segment.url, to: trash.appendingPathComponent(segment.url.lastPathComponent))
        }
    }

    func savedRecordings() -> [Segment] {
        guard let files = try? fm.contentsOfDirectory(at: savedDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        var result: [Segment] = []
        for url in files where url.pathExtension == "mp4" {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            result.append(Segment(url: url, index: 0, startDate: created))
        }
        return result.sorted { $0.startDate > $1.startDate }
    }

    /// 把当前滚动窗口内的分段拼成一段完整视频，保存到 Saved 目录
    func saveCurrentWindow(name: String = "recording") -> URL? {
        let segs = currentSegments()
        guard !segs.isEmpty else { return nil }

        let ts = DateFormatter()
        ts.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(name)_\(ts.string(from: Date())).mp4"
        let dest = savedDir.appendingPathComponent(fileName)

        if segs.count == 1 {
            try? fm.copyItem(at: segs[0].url, to: dest)
            return dest
        }

        // 多段用 AVFoundation 无损拼接（不重新编码，速度快、省电）
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        for seg in segs {
            let asset = AVURLAsset(url: seg.url)
            let duration = asset.duration
            if let v = asset.tracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration), of: v, at: cursor
                )
            }
            if let a = asset.tracks(withMediaType: .audio).first, let at = audioTrack {
                try? at.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration), of: a, at: cursor
                )
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough
        ) else { return nil }
        exporter.outputURL = dest
        exporter.outputFileType = .mp4
        let semaphore = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously { semaphore.signal() }
        semaphore.wait()
        return exporter.status == .completed ? dest : nil
    }

    func clearAll(permanently: Bool) {
        for seg in currentSegments() { delete(segment: seg, permanently: permanently) }
    }
}
