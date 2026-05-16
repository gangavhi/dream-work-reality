import SwiftUI

struct ScanReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let payload: ScanReviewPayload

    @State private var selectedPersonID: String = ""
    @State private var appliedKeys: Set<String> = []
    @State private var showCreatePerson = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Document", value: payload.documentType.rawValue)
                    LabeledContent("Pages", value: "\(payload.pageCount)")
                    LabeledContent("Text regions", value: "\(payload.ocrBlockCount)")
                }

                Section("Apply to profile") {
                    if appState.people.isEmpty {
                        Text("Add a household member first, or create one below.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Person", selection: $selectedPersonID) {
                            Text("Select a person…").tag("")
                            ForEach(appState.people) { person in
                                Text(person.displayTitle).tag(person.id)
                            }
                        }

                        if selectedPersonID.isEmpty, !payload.suggestions.isEmpty {
                            Text(
                                "The scan name does not match an existing profile. Create a new person from the scan, or pick someone to update manually."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button("Create new person from scan") {
                        showCreatePerson = true
                    }
                }

                if payload.suggestions.isEmpty {
                    Section("Suggested fields") {
                        Text("No structured fields detected. Review raw text below and edit the profile manually.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Suggested fields") {
                        ForEach(payload.suggestions) { suggestion in
                            Toggle(isOn: binding(for: suggestion.profileKey)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.label)
                                        .font(.headline)
                                    Text(suggestion.value)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Confidence: \(suggestion.confidence)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section("Raw OCR text") {
                    Text(payload.fullText)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Review scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save to profile") {
                        saveSelectedFields()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedPersonID.isEmpty {
                    selectedPersonID = defaultPersonID()
                }
                appliedKeys = Set(payload.suggestions.map(\.profileKey))
            }
            .sheet(isPresented: $showCreatePerson) {
                NavigationStack {
                    PersonEditorView(
                        person: suggestedNewPerson(),
                        isNew: true
                    ) { saved in
                        selectedPersonID = saved.id
                        showCreatePerson = false
                    }
                }
            }
            .alert(
                "Profile updated",
                isPresented: Binding(
                    get: { saveMessage != nil },
                    set: { if !$0 { saveMessage = nil } }
                )
            ) {
                Button("OK") {
                    saveMessage = nil
                    dismiss()
                }
            } message: {
                if let saveMessage {
                    Text(saveMessage)
                }
            }
        }
    }

    private var canSave: Bool {
        !selectedPersonID.isEmpty && !appliedKeys.isEmpty
    }

    /// Prefer a profile whose name matches OCR; avoid silently merging into unrelated demo/sample rows.
    private func defaultPersonID() -> String {
        guard let scannedName = payload.suggestions
            .first(where: { $0.profileKey == ProfileFieldKey.displayName })?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !scannedName.isEmpty
        else {
            return appState.people.first?.id ?? ""
        }

        let normalized = scannedName.lowercased()
        if let match = appState.people.first(where: {
            $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }) {
            return match.id
        }
        return ""
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { appliedKeys.contains(key) },
            set: { enabled in
                if enabled {
                    appliedKeys.insert(key)
                } else {
                    appliedKeys.remove(key)
                }
            }
        )
    }

    private func suggestedNewPerson() -> PersonRecord {
        var person = PersonRecord.empty()
        let updates = payload.suggestions
            .filter { appliedKeys.contains($0.profileKey) }
            .reduce(into: [String: String]()) { $0[$1.profileKey] = $1.value }
        person = person.merged(with: updates)
        if person.value(for: ProfileFieldKey.displayName).isEmpty,
           let name = updates[ProfileFieldKey.displayName]
        {
            person = person.withValue(name, for: ProfileFieldKey.displayName)
        }
        return person
    }

    private func saveSelectedFields() {
        guard var person = appState.people.first(where: { $0.id == selectedPersonID }) else { return }
        let updates = payload.suggestions
            .filter { appliedKeys.contains($0.profileKey) }
            .reduce(into: [String: String]()) { $0[$1.profileKey] = $1.value }
        person = person.merged(with: updates)
        if appState.savePerson(person) {
            saveMessage = "Saved \(updates.count) field(s) to \(person.displayTitle)."
        } else {
            saveMessage = "Could not save profile."
        }
    }
}
