import SwiftUI
import UIKit

struct RecorderView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var engine: RecorderEngine

    @State private var showPermissionAlert = false
    @State private var showSaveToast = false
    @State private var saveMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                // 相机预览铺满
                CameraPreview(session: engine.previewSession)
                    .ignoresSafeArea()

                // 顶部状态条
                VStack {
                    HStack {
                        statusBadge
                        Spacer()
                        if engine.state == .recording {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text(formatElapsed(engine.elapsedSeconds))
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundColor(.white)
                        }
                    }
                    .padding()
                    Spacer()
                }

                // 底部控制区
                VStack(spacing: 18) {
                    if engine.state == .recording {
                        HStack(spacing: 24) {
                            segmentInfo
                            Divider().frame(height: 30).colorMultiply(.gray)
                            saveButton
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundColor(.white)
                    }

                    recordButton
                    Text(engine.state == .recording ? "点按停止录像" : "点按开始循环录像")
                        .font(.caption).foregroundColor(.white.opacity(0.75))
                }
                .padding(.bottom, 28)
            }
            .navigationTitle("AlibiCam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill").foregroundColor(.white)
                    }
                }
            }
            .alert("权限不足", isPresented: $showPermissionAlert) {
                Button("去设置", role: .none) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请允许相机与麦克风权限后重试")
            }
            .overlay(alignment: .top) {
                if showSaveToast {
                    Text(saveMessage)
                        .font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundColor(.white)
                        .padding(.top, 60)
                        .transition(.opacity)
                }
            }
            .onChange(of: engine.autoStopped) { stopped in
                if stopped { saveMessage = "检测到异常移动，已自动停止并保留片段"; showSaveToast = true }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .foregroundColor(.white)
    }

    private var statusColor: Color {
        switch engine.state {
        case .recording: return .red
        case .preparing: return .orange
        case .error: return .pink
        default: return .gray
        }
    }

    private var statusText: String {
        switch engine.state {
        case .recording: return "录像中"
        case .preparing: return "准备中…"
        case .error: return engine.errorMessage ?? "出错"
        case .paused: return "已暂停"
        case .idle: return "待机"
        }
    }

    private var segmentInfo: some View {
        VStack(spacing: 2) {
            Text("分段").font(.caption2).foregroundColor(.white.opacity(0.6))
            Text("\(engine.segmentCount) 段").font(.subheadline.weight(.semibold))
            Text("每 \(settings.intervalMinutes) 分钟").font(.caption2).foregroundColor(.white.opacity(0.6))
        }
    }

    private var saveButton: some View {
        Button {
            saveCurrent()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "square.and.arrow.down").font(.title3)
                Text("保存").font(.caption2)
            }
        }
    }

    private var recordButton: some View {
        Button {
            if engine.state == .recording {
                engine.startMotion()
                engine.stop()
            } else {
                if !RecorderEngine.checkPermission() {
                    showPermissionAlert = true
                    return
                }
                engine.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    engine.startMotion()
                    engine.startTimers()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(engine.state == .recording ? Color.white : Color.red)
                    .frame(width: 78, height: 78)
                if engine.state == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Color.white).frame(width: 30, height: 30)
                }
            }
            .shadow(radius: 6)
        }
    }

    private func saveCurrent() {
        if let url = SegmentStore.shared.saveCurrentWindow() {
            saveMessage = "已保存：\(url.lastPathComponent)"
        } else {
            saveMessage = "暂无可保存的录像"
        }
        showSaveToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showSaveToast = false }
    }

    private func formatElapsed(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }
}
