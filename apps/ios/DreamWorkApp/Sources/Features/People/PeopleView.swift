import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresentingNew = false

    var body: some View {
        NavigationStack {
            List {
                if appState.peopleStore.people.isEmpty {
                    ContentUnavailableView("No people yet", systemImage: "person.crop.circle.badge.plus", description: Text("Create a profile like “Sreeni” so scanned details can be saved under People."))
                } else {
                    Section("People") {
                        ForEach(appState.peopleStore.people) { person in
                            NavigationLink {
                                EditPersonProfileView(initial: person) { updated in
                                    appState.peopleStore.upsert(updated, select: true)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.displayTitle)
                                    if let fn = person.firstName, let ln = person.lastName {
                                        Text("\(fn) \(ln)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx {
                                let id = appState.peopleStore.people[i].id
                                appState.peopleStore.delete(id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { isPresentingNew = true }
                }
            }
            .sheet(isPresented: $isPresentingNew) {
                NavigationStack {
                    EditPersonProfileView(initial: PersonProfile(nickname: "")) { created in
                        appState.peopleStore.upsert(created, select: true)
                    }
                }
            }
        }
    }
}
