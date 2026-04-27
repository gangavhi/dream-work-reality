import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(AppTab.scan)

            PeopleView()
                .tabItem {
                    Label("People", systemImage: "person.2")
                }
                .tag(AppTab.people)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }
}
