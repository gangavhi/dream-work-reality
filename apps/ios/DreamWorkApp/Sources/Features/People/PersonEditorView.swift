import SwiftUI

struct PersonEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PersonRecord
    @State private var fieldValues: [String: String]
    @State private var relationship: HouseholdRelationship
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    let isNew: Bool
    var onSaved: ((PersonRecord) -> Void)?
    var onDeleted: (() -> Void)?

    init(
        person: PersonRecord,
        isNew: Bool,
        onSaved: ((PersonRecord) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: person)
        _fieldValues = State(initialValue: Dictionary(uniqueKeysWithValues: person.fields.map { ($0.key, $0.value) }))
        let rel = person.value(for: ProfileFieldKey.relationship)
        _relationship = State(initialValue: HouseholdRelationship.allCases.first { $0.rawValue == rel } ?? .selfMember)
        self.isNew = isNew
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    private var labelContext: DocumentFieldLabelContext {
        DocumentFieldLabelContext.from(fieldValues: fieldValues, documentType: .driversLicense)
    }

    var body: some View {
        Form {
            Section("Household") {
                Picker("Role", selection: $relationship) {
                    ForEach(HouseholdRelationship.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                TextField("Display name", text: binding(for: ProfileFieldKey.displayName))
                    .fieldInputStyle()
                    .textContentType(.name)
            }

            ForEach(ProfileSection.allCases) { section in
                let fields = ProfileSchema.fields(in: section)
                if !fields.isEmpty {
                    Section(section.rawValue) {
                        ForEach(fields) { field in
                            if field.key != ProfileFieldKey.displayName,
                               field.key != ProfileFieldKey.relationship
                            {
                                fieldRow(field)
                            }
                        }
                    }
                }
            }

            let extensionKeys = fieldValues.keys.filter { !ProfileSchema.isCanonicalKey($0) }.sorted()
            if !extensionKeys.isEmpty {
                Section("Additional fields") {
                    ForEach(extensionKeys, id: \.self) { key in
                        TextField(ProfileSchema.label(forExtensionKey: key), text: binding(for: key))
                            .fieldInputStyle()
                    }
                }
            }

            if !isNew {
                Section {
                    Button("Delete and wipe profile", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New person" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .confirmationDialog(
            "Delete \(draft.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete and wipe profile", role: .destructive) {
                deleteProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes this profile and all saved fields from this device.")
        }
        .alert("Could not save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: ProfileFieldDefinition) -> some View {
        let label = ProfileSchema.contextualLabel(for: field.key, context: labelContext)
        TextField(label, text: binding(for: field.key))
            .fieldInputStyle()
            .textContentType(ProfileFieldInputTraits.textContentType(for: field.key))
            .keyboardType(ProfileFieldInputTraits.keyboardType(for: field.key))
            .textInputAutocapitalization(ProfileFieldInputTraits.textInputAutocapitalization(for: field.key))
            .autocorrectionDisabled(ProfileFieldInputTraits.autocorrectionDisabled(for: field.key))
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fieldValues[key, default: ""] },
            set: { fieldValues[key] = $0 }
        )
    }

    private func save() {
        var fields: [PersonRecord.Field] = []
        fieldValues[ProfileFieldKey.relationship] = relationship.rawValue
        for (key, value) in fieldValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            fields.append(PersonRecord.Field(key: key, value: trimmed))
        }
        fields.sort { $0.key < $1.key }
        let person = PersonRecord(id: draft.id, fields: fields)
        guard appState.savePerson(person) else {
            errorMessage = "Rust core could not persist this profile."
            return
        }
        onSaved?(person)
        dismiss()
    }

    private func deleteProfile() {
        guard appState.deletePerson(id: draft.id) else {
            errorMessage = "Could not delete this profile."
            return
        }
        onDeleted?()
        dismiss()
    }
}
