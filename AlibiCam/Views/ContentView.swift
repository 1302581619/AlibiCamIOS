import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecorderView()
                .tabItem {
                    Label("录制", systemImage: "video")
                }
            SavedFilesView()
                .tabItem {
                    Label("录像", systemImage: "folder")
                }
        }
        .tint(.red)
    }
}
