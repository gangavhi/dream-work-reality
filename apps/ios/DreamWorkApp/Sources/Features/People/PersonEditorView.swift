import SwiftUI

struct PersonEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PersonRecord
    @State private var fieldValues: [String: String]
    @State private var relationship: HouseholdRelationship
    @State private var errorMessage: String?

    let isNew: Bool
    var onSaved: ((PersonRecord) -> Void)?

    init(person: PersonRecord, isNew: Bool, onSaved: ((PersonRecord) -> Void)? = nil) {
        _draft = State(initialValue: person)
        _fieldValues = State(initialValue: Dictionary(uniqueKeysWithValues: person.fields.map { ($0.key, $0.value) }))
        let rel = person.value(for: ProfileFieldKey.relationship)
        _relationship = State(initialValue: HouseholdRelationship.allCases.first { $0.rawValue == rel } ?? .selfMember)
        self.isNew = isNew
        self.onSaved = onSaved
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
        if field.isSensitive {
            SecureField(field.label, text: binding(for: field.key))
        } else {
            TextField(field.label, text: binding(for: field.key))
                .textContentType(textContentType(for: field.key))
                .keyboardType(keyboardType(for: field.key))
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fieldValues[key, default: ""] },
            set: { fieldValues[key] = $0 }
        )
    }

    private func textContentType(for key: String) -> UITextContentType? {
        switch key {
        case ProfileFieldKey.email: return .emailAddress
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome, ProfileFieldKey.emergencyContactPhone:
            return .telephoneNumber
        case ProfileFieldKey.addressLine1: return .streetAddressLine1
        case ProfileFieldKey.addressLine2: return .streetAddressLine2
        case ProfileFieldKey.city: return .addressCity
        case ProfileFieldKey.state: return .addressState
        case ProfileFieldKey.postalCode: return .postalCode
        default: return nil
        }
    }

    private func keyboardType(for key: String) -> UIKeyboardType {
        switch key {
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome, ProfileFieldKey.emergencyContactPhone:
            return .phonePad
        case ProfileFieldKey.email: return .emailAddress
        default: return .default
        }
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
}
