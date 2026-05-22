import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var person: PersonRecord
    @State private var fieldDrafts: [String: String] = [:]
    @State private var editingFieldKey: String?
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var fieldSaveError: String?

    init(person: PersonRecord) {
        _person = State(initialValue: person)
    }

    private var labelContext: DocumentFieldLabelContext {
        DocumentFieldLabelContext.from(person: person)
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
                            editableFieldRow(
                                key: field.key,
                                label: ProfileSchema.contextualLabel(for: field.key, context: labelContext),
                                value: value
                            )
                        }
                    }
                }
            }

            let extensionFields = person.fields.filter { !ProfileSchema.isCanonicalKey($0.key) && !$0.value.isEmpty }
            if !extensionFields.isEmpty {
                Section("Additional fields") {
                    ForEach(extensionFields, id: \.key) { field in
                        editableFieldRow(
                            key: field.key,
                            label: ProfileSchema.label(forExtensionKey: field.key),
                            value: field.value
                        )
                    }
                }
            }
        }
        .appListChrome()
        .navigationTitle(person.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit all") { showEditor = true }
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
                } onDeleted: {
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Delete \(person.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete and wipe profile", role: .destructive) {
                if appState.deletePerson(id: person.id) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes this profile and all saved fields from this device.")
        }
        .onAppear {
            if let latest = appState.people.first(where: { $0.id == person.id }) {
                person = latest
            }
            syncFieldDraftsFromPerson()
        }
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { fieldSaveError != nil },
                set: { if !$0 { fieldSaveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fieldSaveError ?? "")
        }
    }

    @ViewBuilder
    private func editableFieldRow(key: String, label: String, value: String) -> some View {
        EditableFieldRow(
            label: label,
            profileKey: key,
            text: fieldBinding(for: key, fallback: value),
            isEditing: editingBinding(for: key),
            originalValue: person.value(for: key),
            onCommit: { saveField(key: key) }
        )
    }

    private func fieldBinding(for key: String, fallback: String) -> Binding<String> {
        Binding(
            get: { fieldDrafts[key, default: fallback] },
            set: { fieldDrafts[key] = $0 }
        )
    }

    private func editingBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { editingFieldKey == key },
            set: { isEditing in
                if isEditing {
                    editingFieldKey = key
                } else if editingFieldKey == key {
                    editingFieldKey = nil
                }
            }
        )
    }

    private func syncFieldDraftsFromPerson() {
        var drafts: [String: String] = [:]
        for field in person.fields {
            drafts[field.key] = field.value
        }
        fieldDrafts = drafts
    }

    private func saveField(key: String) {
        let trimmed = fieldDrafts[key, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = person.withValue(trimmed, for: key)
        guard appState.savePerson(updated) else {
            let label = ProfileSchema.definition(for: key)?.label
                ?? ProfileSchema.label(forExtensionKey: key)
            fieldSaveError = "Could not save \(label)."
            syncFieldDraftsFromPerson()
            return
        }
        person = updated
        fieldDrafts[key] = trimmed
    }
}
