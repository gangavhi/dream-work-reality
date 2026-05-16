import SwiftUI

struct ScanReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let payload: ScanReviewPayload

    @State private var selectedPersonID: String = ""
    @State private var appliedKeys: Set<String> = []
    @State private var showCreatePerson = false
    @State private var saveMessage: String?

    private static let highConfidenceMatchThreshold = 0.72

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("You selected", value: payload.userDocumentType.rawValue)
                    if let understanding = payload.understanding {
                        LabeledContent("AI document type", value: formatDocumentType(understanding.documentType))
                        LabeledContent(
                            "Type confidence",
                            value: percentLabel(understanding.documentTypeConfidence)
                        )
                        if let region = understanding.issuerRegion, !region.isEmpty {
                            LabeledContent("Issuer / region", value: region)
                        }
                        if let hint = understanding.displayNameHint, !hint.isEmpty {
                            LabeledContent("Name hint", value: hint)
                        }
                    } else if DevAPIKeyStore.openAIAPIKey == nil {
                        Text("Add an OpenAI API key in Settings for accurate field mapping (name, address, DL #, issue/expiry). Without it, only basic heuristics are used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Pages", value: "\(payload.pageCount)")
                    LabeledContent("Text regions", value: "\(payload.ocrBlockCount)")
                }

                if let plan = payload.storagePlan, !plan.operations.isEmpty {
                    Section("Storage plan") {
                        LabeledContent(
                            "Profile fields",
                            value: "\(plan.summary.canonicalCount)"
                        )
                        LabeledContent(
                            "Extension fields",
                            value: "\(plan.summary.extensionCount)"
                        )
                        ForEach(plan.operations) { op in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ProfileSchema.definition(for: op.key)?.label ?? op.key)
                                    .font(.subheadline)
                                Text(op.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(op.targetLabel) · \(op.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                if let resolution = payload.personResolution, !appState.people.isEmpty {
                    Section("Person match") {
                        LabeledContent("Suggestion", value: resolutionLabel(resolution.resolution))
                        LabeledContent("Confidence", value: percentLabel(resolution.confidence))

                        if resolution.resolution == .ambiguous {
                            Text("Multiple profiles look similar. Pick the correct person below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if resolution.resolution == .newPerson {
                            Text("This scan looks like a new household member.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !resolution.candidates.isEmpty {
                            ForEach(resolution.candidates.prefix(5)) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(personTitle(for: candidate.personID))
                                        .font(.subheadline)
                                    Text("Score: \(percentLabel(candidate.score))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !candidate.reasonSummary.isEmpty {
                                        Text(candidate.reasonSummary)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
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

                    if payload.personResolution?.resolution == .newPerson,
                       let prefilled = payload.prefilledPerson
                    {
                        Button("Save as new person") {
                            saveNewPerson(prefilled)
                        }
                        .disabled(prefilled.value(for: ProfileFieldKey.displayName).isEmpty)
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

    private func defaultPersonID() -> String {
        if let resolution = payload.personResolution,
           resolution.resolution == .matchExisting,
           let personID = resolution.personID,
           resolution.confidence >= Self.highConfidenceMatchThreshold,
           appState.people.contains(where: { $0.id == personID })
        {
            return personID
        }

        guard let scannedName = payload.suggestions
            .first(where: { $0.profileKey == ProfileFieldKey.displayName })?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !scannedName.isEmpty
        else {
            return ""
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
        let updates = payload.suggestions
            .filter { appliedKeys.contains($0.profileKey) }
            .reduce(into: [String: String]()) { $0[$1.profileKey] = $1.value }

        var person = payload.prefilledPerson ?? PersonRecord.empty()
        person = person.merged(with: updates)
        if person.value(for: ProfileFieldKey.displayName).isEmpty,
           let name = updates[ProfileFieldKey.displayName]
        {
            person = person.withValue(name, for: ProfileFieldKey.displayName)
        }
        return person
    }

    private func saveNewPerson(_ person: PersonRecord) {
        let updates = payload.suggestions
            .filter { appliedKeys.contains($0.profileKey) }
            .reduce(into: [String: String]()) { $0[$1.profileKey] = $1.value }
        let merged = person.merged(with: updates)
        if appState.savePerson(merged) {
            saveMessage = "Created \(merged.displayTitle) under People."
        } else {
            saveMessage = "Could not create profile."
        }
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

    private func personTitle(for id: String) -> String {
        appState.people.first(where: { $0.id == id })?.displayTitle ?? id
    }

    private func resolutionLabel(_ kind: PersonResolutionKind) -> String {
        switch kind {
        case .matchExisting: return "Existing profile"
        case .newPerson: return "New person"
        case .ambiguous: return "Ambiguous — choose manually"
        }
    }

    private func formatDocumentType(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func percentLabel(_ value: Double) -> String {
        let pct = Int((value * 100).rounded())
        return "\(pct)%"
    }
}
