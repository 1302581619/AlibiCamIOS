import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings

    private static let durations = [5, 10, 15, 20, 30, 45, 60]
    private static let intervals = [1, 2, 3, 5, 10]
    private static let fpsOptions = [15, 24, 30, 60]
    private static let bitrates = [1, 2, 4, 6]

    var body: some View {
        List {
            Section("录像时长") {
                Picker("保留最近", selection: $settings.maxDurationMinutes) {
                    ForEach(Self.durations, id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                Picker("分段间隔", selection: $settings.intervalMinutes) {
                    ForEach(Self.intervals, id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                Text("循环录像保留最近 \(settings.maxDurationMinutes) 分钟的片段，每 \(settings.intervalMinutes) 分钟切一段，超出部分自动删除。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("画面") {
                Picker("画质", selection: $settings.quality) {
                    ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
                }
                Picker("帧率", selection: $settings.frameRate) {
                    ForEach(Self.fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("码率", selection: $settings.bitRateMbps) {
                    ForEach(Self.bitrates, id: \.self) { Text("\($0) Mbps").tag($0) }
                }
                Picker("摄像头", selection: $settings.cameraPosition) {
                    ForEach(CameraPosition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("录制声音", isOn: $settings.recordAudio)
                Toggle("视频防抖 (EIS)", isOn: $settings.stabilizationEnabled)
            }

            Section("自动停止（姿态感知）") {
                Toggle("检测异常移动自动停止", isOn: $settings.autoStopEnabled)
                Picker("灵敏度", selection: $settings.autoStopSensitivity) {
                    ForEach(AutoStopSensitivity.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.autoStopEnabled)
                Text("设备发生剧烈震动或倾倒时自动停止录像并保留片段，适合两轮车 / 行车场景。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("存储") {
                Toggle("永久删除旧片段", isOn: $settings.permanentlyDelete)
                Text("关闭时旧片段移入应用内回收站目录，不会立即释放空间。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section {
                NavigationLink("已保存的录像") { SavedFilesView() }
            }

            Section("关于") {
                Text("AlibiCam iOS · 基于 Alibi-Cam (GPL v3) 复刻的核心循环录像功能")
                    .font(.caption).foregroundColor(.secondary)
                Text("版本 1.0.0 (build 1)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
