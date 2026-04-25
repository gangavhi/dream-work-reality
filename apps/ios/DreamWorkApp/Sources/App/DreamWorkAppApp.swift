import SwiftUI

@main
struct DreamWorkAppApp: App {
    @StateObject private var appState = AppState(coreService: RustCoreBridgeService())

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .task {
                    // Demo convenience: open the school intake form on launch.
                    appState.openSchoolIntakeForm()
                }
        }
    }
}
