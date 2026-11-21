import SwiftUI

@main
struct AlibiCamApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState.settings)
                .environmentObject(appState.engine)
        }
    }
}
