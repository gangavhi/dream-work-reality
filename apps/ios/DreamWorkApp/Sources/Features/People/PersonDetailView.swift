import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var person: PersonRecord
    @State private var showEditor = false
    @State private var showDeleteConfirm = false

    init(person: PersonRecord) {
        _person = State(initialValue: person)
    }

    var body: some View {
        List {
            ForEach(ProfileSection.allCases) { section in
                let items = ProfileSchema.fields(in: section).compactMap { field -> (ProfileFieldDefinition, String)? in
                    let value = person.value(for: field.key)
                    guard field.key == ProfileFieldKey.displayName
                        || field.key == ProfileFieldKey.relationship
                        || !value.isEmpty
                    else { return nil }
                    return (field, value)
                }
                if !items.isEmpty {
                    Section(section.rawValue) {
                        ForEach(items, id: \.0.key) { field, value in
                            LabeledContent(field.label) {
                                Text(masked(field: field, value: value))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(person.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                PersonEditorView(person: person, isNew: false) { updated in
                    person = updated
                }
            }
        }
        .confirmationDialog(
            "Delete \(person.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete profile", role: .destructive) {
                if appState.deletePerson(id: person.id) {
                    // Pop handled by list refresh when user navigates back.
                }
            }
        }
        .onAppear {
            if let latest = appState.people.first(where: { $0.id == person.id }) {
                person = latest
            }
        }
    }

    private func masked(field: ProfileFieldDefinition, value: String) -> String {
        guard field.isSensitive, value.count > 4 else { return value }
        return String(repeating: "•", count: max(4, value.count - 4)) + value.suffix(4)
    }
}
