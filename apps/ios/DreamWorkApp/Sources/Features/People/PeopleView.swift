import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddPerson = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.people.isEmpty {
                    ContentUnavailableView {
                        Label("No profiles yet", systemImage: "person.3.fill")
                            .font(.title2)
                    } description: {
                        Text("Add household members manually, or scan a document on Home and save the extracted fields.")
                            .appHelperText()
                            .multilineTextAlignment(.center)
                    } actions: {
                        Button("Add person") { showAddPerson = true }
                            .buttonStyle(.borderedProminent)
                        Button("Load demo profiles") { appState.seedSamplePeople() }
                            .accessibilityIdentifier("peopleLoadSamplesButton")
                    }
                    .accessibilityIdentifier("peopleEmptyState")
                } else {
                    List {
                        ForEach(appState.people) { person in
                            NavigationLink {
                                PersonDetailView(person: person)
                            } label: {
                                personRow(person)
                            }
                            .accessibilityIdentifier("peopleRow_\(person.id)")
                        }
                        .onDelete(perform: deletePeople)
                    }
                    .appListChrome()
                    .accessibilityIdentifier("peopleList")
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddPerson = true
                    } label: {
                        Label("Add person", systemImage: "plus")
                    }
                    .accessibilityIdentifier("peopleAddButton")
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

    @ViewBuilder
    private func personRow(_ person: PersonRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent.opacity(0.85))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(person.displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                let role = person.value(for: ProfileFieldKey.relationship)
                if !role.isEmpty {
                    AppTag(text: role)
                }

                let dl = person.value(for: ProfileFieldKey.driversLicenseNumber)
                if !dl.isEmpty {
                    Text("DL •••• \(String(dl.suffix(4)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            let id = appState.people[index].id
            _ = appState.deletePerson(id: id)
        }
    }
}
