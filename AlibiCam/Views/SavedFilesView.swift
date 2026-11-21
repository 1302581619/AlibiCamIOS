import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct SavedFilesView: View {
    @State private var files: [Segment] = []
    @State private var playing: IdentifiableURL?
    @State private var showShare = false
    @State private var shareItems: [URL] = []

    var body: some View {
        List {
            if files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("暂无录像")
                        .font(.headline)
                    Text("回到录制页点按「保存」，即可把当前循环窗口内的片段拼接成一段完整录像")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(files) { file in
                    HStack {
                        Image(systemName: "video.fill").foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.url.lastPathComponent)
                                .font(.subheadline).lineLimit(1)
                            Text("\(file.durationText) · \(file.sizeText)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            shareItems = [file.url]
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { playing = IdentifiableURL(url: file.url) }
                }
                .onDelete { idx in
                    for i in idx {
                        try? FileManager.default.removeItem(at: files[i].url)
                    }
                    files.remove(atOffsets: idx)
                }
            }
        }
        .navigationTitle("已保存的录像")
        .onAppear { reload() }
        .sheet(item: $playing) { item in
            PlayerView(url: item.url)
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
    }

    private func reload() {
        files = SegmentStore.shared.savedRecordings()
    }
}

struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.play()
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
