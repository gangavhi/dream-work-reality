import SwiftUI

@main
struct TrustNestApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appState)
        }
    }
}
