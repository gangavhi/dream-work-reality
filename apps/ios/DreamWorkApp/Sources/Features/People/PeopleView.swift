import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddPerson = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.people.isEmpty {
                    ContentUnavailableView {
                        Label("No profiles yet", systemImage: "person.3")
                    } description: {
                        Text("Add household members manually or save fields from a document scan on Home.")
                    } actions: {
                        Button("Add person") { showAddPerson = true }
                        Button("Load demo profiles (Alex Carter, …)") { appState.seedSamplePeople() }
                            .accessibilityIdentifier("peopleLoadSamplesButton")
                    }
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
                                    let role = person.value(for: ProfileFieldKey.relationship)
                                    if !role.isEmpty {
                                        Text(role)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("peopleRow_\(person.id)")
                            }
                        }
                        .onDelete(perform: deletePeople)
                    }
                    .accessibilityIdentifier("peopleList")
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddPerson = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("peopleAddButton")
                }
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") {
                        appState.refreshPeopleList()
                    }
                }
            }
            .onAppear {
                appState.refreshPeopleList()
            }
            .refreshable {
                appState.refreshPeopleList()
            }
            .sheet(isPresented: $showAddPerson) {
                NavigationStack {
                    PersonEditorView(person: .empty(), isNew: true)
                }
            }
        }
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            let id = appState.people[index].id
            _ = appState.deletePerson(id: id)
        }
    }
}
