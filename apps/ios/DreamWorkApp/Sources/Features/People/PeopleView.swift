import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("People Screen")
                    .font(.title2)
                Text("Loaded person: \(appState.selectedPersonName)")
                    .accessibilityIdentifier("peopleLoadedPersonName")
                Text("Manual entries in Rust core: \(appState.manualEntryCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("peopleManualEntryCount")
                Button("Save + Load Demo Person") {
                    appState.saveAndLoadDemoPerson()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("peopleSaveLoadButton")
            }
            .navigationTitle("People")
            .padding()
        }
    }
}
