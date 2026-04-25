import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Home Screen")
                    .font(.title2)
                    .accessibilityIdentifier("homeScreenTitle")

                Text(appState.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeStatusText")

                Text("Manual entries: \(appState.manualEntryCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeManualEntryCount")

                Button("Refresh Core Status") {
                    appState.refreshStatus()
                }
                .buttonStyle(.borderedProminent)

                Button("Save + Load Demo Person") {
                    appState.saveAndLoadDemoPerson()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("saveLoadPersonButton")

                Button("Open School Intake Form") {
                    appState.openSchoolIntakeForm()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}
