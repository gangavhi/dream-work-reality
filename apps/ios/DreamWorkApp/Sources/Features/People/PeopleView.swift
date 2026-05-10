import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.3",
                        description: Text("Add sample entries stored in the Rust core, or save people from Home.")
                    )
                    .accessibilityIdentifier("peopleEmptyState")
                } else {
                    List {
                        ForEach(appState.people) { person in
                            NavigationLink {
                                PersonDetailView(person: person)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(person.displayTitle)
                                        .font(.headline)
                                    Text(person.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("peopleRow_\(person.id)")
                            }
                        }
                    }
                    .accessibilityIdentifier("peopleList")
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add samples") {
                        appState.seedSamplePeople()
                    }
                    .accessibilityIdentifier("peopleAddSamplesButton")
                }
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") {
                        appState.refreshPeopleList()
                    }
                    .accessibilityIdentifier("peopleRefreshButton")
                }
            }
            .onAppear {
                appState.refreshPeopleList()
            }
            .refreshable {
                appState.refreshPeopleList()
            }
        }
    }
}
