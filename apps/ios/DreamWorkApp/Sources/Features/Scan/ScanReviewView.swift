import SwiftUI

struct ScanReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let payload: ScanReviewPayload

    @State private var selectedPersonID: String = ""
    @State private var editedValues: [String: String] = [:]
    @State private var originalValues: [String: String] = [:]
    @State private var editingFieldKey: String?
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            List {
                documentSummarySection
                onDeviceExtractionSection
                if shouldShowTelemetry {
                    telemetrySection
                }
                profileTargetSection

                if payload.suggestions.isEmpty {
                    Section {
                        Text("No fields detected from this scan.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groupedFieldSections) { group in
                        Section(group.title) {
                            ForEach(group.items, id: \.profileKey) { suggestion in
                                fieldRow(suggestion)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review scan")
            .navigationBarTitleDisplayMode(.inline)
            .appListChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.clearPendingScanSession()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFields()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                let initial = Dictionary(
                    uniqueKeysWithValues: payload.suggestions.map { ($0.profileKey, $0.value) }
                )
                editedValues = initial
                originalValues = initial
                if selectedPersonID.isEmpty {
                    selectedPersonID = defaultPersonID()
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
                    appState.clearPendingScanSession()
                    dismiss()
                }
            } message: {
                if let saveMessage {
                    Text(saveMessage)
                }
            }
        }
    }

    private var groupedFieldSections: [ProfileSchema.FieldGroup] {
        ProfileSchema.groupedSuggestions(payload.suggestions)
    }

    private var shouldShowTelemetry: Bool {
        #if DEBUG
        return true
        #else
        return payload.suggestions.isEmpty
        #endif
    }

    @ViewBuilder
    private var onDeviceExtractionSection: some View {
        if GenAISettings.provider == .onDevice, OnDeviceMLPolicy.requiresManualExtractionTrigger {
            Section {
                if appState.isRunningOnDeviceExtraction {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Running on-device extraction…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(OnDeviceMLPolicy.manualExtractionButtonTitle) {
                        Task { await appState.runOnDeviceExtractionForCurrentScan() }
                    }
                }
                if payload.suggestions.isEmpty {
                    Text(OnDeviceMLPolicy.manualExtractionExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var documentSummarySection: some View {
        Section {
            Label(payload.openDocumentTypeLabel, systemImage: payload.detectedDocumentType.iconName)
            if payload.usedMachineReadablePayload {
                Text("High-confidence fields from barcode or machine-readable zone on the document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if payload.usedAI, !payload.usedHeuristicFallback {
                Text("Extracted on this device (no data sent to the internet).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if payload.usedHeuristicFallback {
                Text("Fields are estimated from text patterns — verify each value against the scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Limited fields detected. Enter missing details manually or try a clearer scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notice = payload.mappingNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Document")
        }
    }

    @ViewBuilder
    private var telemetrySection: some View {
        Section {
            if payload.suggestions.isEmpty {
                Text("No fields reached review. Pipeline trace below shows where extraction stopped or fell back.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if mappingSourceSummary.isEmpty {
                Text("Mapping sources: none")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Mapping sources: \(mappingSourceSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !payload.pipelineTrace.isEmpty {
                Text(payload.pipelineTrace.joined(separator: " → "))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Pipeline telemetry")
        }
    }

    private var mappingSourceSummary: String {
        let counts = Dictionary(grouping: payload.suggestions) { suggestion in
            suggestion.mappingSource?.displayLabel ?? "Unknown"
        }
        return counts
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var profileTargetSection: some View {
        Section {
            if appState.people.isEmpty {
                Label("A new profile will be created when you save.", systemImage: "person.badge.plus")
                    .foregroundStyle(.secondary)
            } else if let match = resolvedProfileMatch {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Updating existing profile")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.green)
                    }

                    if let person = appState.people.first(where: { $0.id == match.personID }) {
                        Text(person.displayTitle)
                            .font(.subheadline.weight(.semibold))
                    }

                    if !match.reasons.isEmpty {
                        Text(matchReasonSummary(match.reasons))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if appState.people.count > 1 {
                        Picker("Profile", selection: $selectedPersonID) {
                            Text("Choose profile…").tag("")
                            ForEach(appState.people) { person in
                                Text(person.displayTitle).tag(person.id)
                            }
                        }
                    }
                }
            } else if payload.personResolution?.resolution == .ambiguous {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Multiple profiles may match", systemImage: "person.2.circle")
                        .font(.headline)
                    Text("Pick the profile to update, or save to create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Profile", selection: $selectedPersonID) {
                        Text("Create new profile").tag("")
                        ForEach(appState.people) { person in
                            Text(person.displayTitle).tag(person.id)
                        }
                    }
                }
            } else {
                Label("No matching profile found — a new profile will be created.", systemImage: "person.badge.plus")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Save to profile")
        }
    }

    private var resolvedProfileMatch: PersonProfileMatcher.MatchResult? {
        PersonProfileMatcher.matchExistingPerson(
            among: appState.people,
            fieldUpdates: currentUpdates(),
            resolution: payload.personResolution
        )
    }

    private func matchReasonSummary(_ reasons: [String]) -> String {
        let labels: [String: String] = [
            "date_of_birth_exact": "date of birth",
            "date_of_birth": "date of birth",
            "legal_last_name_exact": "last name",
            "legal_last_name": "last name",
            "legal_first_name": "first name",
            "name_exact": "name",
            "name_fuzzy": "similar name",
            "display_name_match": "display name",
            "display_name": "display name",
            "address_line1_match": "address",
            "address_line1": "address",
            "postal_code_exact": "ZIP code",
            "postal_code": "ZIP code",
            "drivers_license_number_exact": "driver license number",
            "drivers_license_number": "driver license number",
            "passport_number_exact": "passport number",
            "passport_number": "passport number",
            "dob_and_last_name_combo": "DOB + last name",
            "dob_and_address_combo": "DOB + address",
            "dob_and_postal_combo": "DOB + ZIP",
            "dob_with_secondary_fields": "DOB + other fields",
            "name_and_dob_combo": "name + DOB",
        ]

        let readable = reasons.compactMap { reason -> String? in
            if let exact = labels[reason] { return exact }
            if reason.hasPrefix("name_fuzzy:") { return "similar name" }
            return nil
        }
        let unique = Array(Set(readable)).sorted()
        guard !unique.isEmpty else { return "Matched on shared identity fields." }
        return "Matched on " + unique.joined(separator: ", ")
    }

    @ViewBuilder
    private func fieldRow(_ suggestion: OcrFieldSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EditableFieldRow(
                label: suggestion.label,
                profileKey: suggestion.profileKey,
                text: binding(for: suggestion.profileKey),
                isEditing: editingBinding(for: suggestion.profileKey),
                originalValue: originalValues[suggestion.profileKey, default: ""]
            )
            if suggestion.requiresManualConfirmation {
                Text("Review required — confidence below autofill threshold")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let source = suggestion.mappingSource, source == .estimated || suggestion.isLowConfidence {
                Text("Source: \(source.displayLabel) — verify against scan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let source = suggestion.mappingSource {
                Text("Source: \(source.displayLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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

    private var canSave: Bool {
        !currentUpdates().isEmpty && editingFieldKey == nil
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { editedValues[key, default: ""] },
            set: { editedValues[key] = $0 }
        )
    }

    private func currentUpdates() -> [String: String] {
        editedValues.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func defaultPersonID() -> String {
        if let previous = DocumentFingerprintStore.findPreviousImport(for: payload.fullText) {
            if let personID = previous.personID,
               appState.people.contains(where: { $0.id == personID })
            {
                return personID
            }
            if let name = previous.personName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty,
               let match = appState.people.first(where: { namesMatch($0, scannedName: name) })
            {
                return match.id
            }
        }

        if let match = resolvedProfileMatch {
            return match.personID
        }

        if let nameMatch = appState.people.first(where: { personMatchesScan($0) }) {
            return nameMatch.id
        }

        return ""
    }

    private func personMatchesScan(_ person: PersonRecord) -> Bool {
        let updates = currentUpdates()
        let scannedDisplay = updates[ProfileFieldKey.displayName]
        let scannedFirst = updates[ProfileFieldKey.legalFirstName]
        let scannedLast = updates[ProfileFieldKey.legalLastName]
        let scannedDOB = updates[ProfileFieldKey.dateOfBirth]

        if let scannedDOB, !scannedDOB.isEmpty {
            let personDOB = person.value(for: ProfileFieldKey.dateOfBirth)
            if PersonProfileMatcher.dobMatches(scannedDOB, personDOB) {
                if let scannedLast, !scannedLast.isEmpty {
                    let personLast = person.value(for: ProfileFieldKey.legalLastName)
                    if normalizeName(scannedLast) == normalizeName(personLast) {
                        return true
                    }
                }
                if let scannedDisplay, namesMatch(person, scannedName: scannedDisplay) {
                    return true
                }
            }
        }

        if let scannedDisplay, namesMatch(person, scannedName: scannedDisplay) {
            return true
        }

        if let scannedFirst, let scannedLast {
            let firstLast = "\(scannedFirst) \(scannedLast)"
            let lastFirst = "\(scannedLast) \(scannedFirst)"
            if namesMatch(person, scannedName: firstLast) || namesMatch(person, scannedName: lastFirst) {
                return true
            }

            let personFirst = person.value(for: ProfileFieldKey.legalFirstName)
            let personLast = person.value(for: ProfileFieldKey.legalLastName)
            if !personFirst.isEmpty, !personLast.isEmpty {
                let normalizedScanFirst = normalizeName(scannedFirst)
                let normalizedScanLast = normalizeName(scannedLast)
                let normalizedPersonFirst = normalizeName(personFirst)
                let normalizedPersonLast = normalizeName(personLast)
                if normalizedScanFirst == normalizedPersonFirst,
                   normalizedScanLast == normalizedPersonLast
                {
                    return true
                }
                if normalizedScanFirst == normalizedPersonLast,
                   normalizedScanLast == normalizedPersonFirst
                {
                    return true
                }
            }
        }

        return false
    }

    private func namesMatch(_ person: PersonRecord, scannedName: String) -> Bool {
        normalizeName(person.displayTitle) == normalizeName(scannedName)
    }

    private func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func saveFields() {
        let updates = currentUpdates()
        guard !updates.isEmpty else { return }

        var personID = selectedPersonID
        if personID.isEmpty {
            personID = defaultPersonID()
        }
        if personID.isEmpty,
           let match = PersonProfileMatcher.matchExistingPerson(
               among: appState.people,
               fieldUpdates: updates,
               resolution: payload.personResolution
           )
        {
            personID = match.personID
        }
        if personID.isEmpty,
           let match = appState.people.first(where: { personMatchesScan($0) })
        {
            personID = match.id
        }

        if personID.isEmpty {
            createPerson(from: updates)
            return
        }

        guard var person = appState.people.first(where: { $0.id == personID }) else {
            createPerson(from: updates)
            return
        }

        person = person.merged(with: updates)
        if appState.savePerson(person) {
            recordLearningCorrections(updates: updates)
            let isReimport = DocumentFingerprintStore.findPreviousImport(for: payload.fullText) != nil
            recordIngestAudit(
                person: person,
                fieldCount: updates.count,
                notes: isReimport ? "Updated profile from rescan" : ""
            )
            saveMessage = isReimport
                ? "Updated \(updates.count) field(s) on \(person.displayTitle)."
                : "Added \(updates.count) field(s) to existing profile \(person.displayTitle)."
        } else {
            saveMessage = "Could not save profile."
        }
    }

    private func createPerson(from updates: [String: String]) {
        var person = payload.prefilledPerson ?? PersonRecord.empty()
        person = person.merged(with: updates)
        if person.value(for: ProfileFieldKey.displayName).isEmpty,
           let name = updates[ProfileFieldKey.displayName]
        {
            person = person.withValue(name, for: ProfileFieldKey.displayName)
        }
        if person.value(for: ProfileFieldKey.displayName).isEmpty {
            saveMessage = "Could not save — add a name field to create a profile."
            return
        }
        if appState.savePerson(person) {
            recordLearningCorrections(updates: updates)
            recordIngestAudit(
                person: person,
                fieldCount: updates.count,
                notes: "Created from scan"
            )
            saveMessage = "Created \(person.displayTitle) under People."
        } else {
            saveMessage = "Could not create profile."
        }
    }

    private func recordLearningCorrections(updates: [String: String]) {
        let docType = payload.openDocumentTypeLabel
        for (key, newValue) in updates {
            let original = originalValues[key, default: ""]
            IncrementalLearningStore.record(
                profileKey: key,
                originalValue: original,
                correctedValue: newValue,
                documentType: docType
            )
        }
    }

    private func recordIngestAudit(person: PersonRecord, fieldCount: Int, notes: String = "") {
        DocumentFingerprintStore.record(
            ocrText: payload.fullText,
            personID: person.id,
            personName: person.displayTitle
        )
        IngestAuditLog.append(
            documentType: payload.detectedDocumentType.rawValue,
            personID: person.id,
            personName: person.displayTitle,
            fieldCount: fieldCount,
            usedAI: payload.usedAI,
            notes: notes
        )
    }
}
