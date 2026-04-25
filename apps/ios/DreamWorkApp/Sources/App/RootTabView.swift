import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            PeopleView()
                .tabItem {
                    Label("People", systemImage: "person.2")
                }
                .tag(AppTab.people)

            FormsView()
                .tabItem {
                    Label("Forms", systemImage: "doc.text")
                }
                .tag(AppTab.forms)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }
}
