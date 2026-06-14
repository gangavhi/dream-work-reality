import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var activeProfile: Profile?
    @Published var formURLString: String = ""
    @Published var extractedFields: [FieldExtractionResult] = []
    @Published var isExtracting = false
    @Published var statusMessage: String?

    let database: TrustNestDatabase
    let profileManager: ProfileManager

    init() {
        let database = try! TrustNestDatabase()
        self.database = database
        self.profileManager = ProfileManager(database: database)
    }

    func activateProfile(_ profile: Profile) {
        activeProfile = profile
        statusMessage = "Active profile: \(profile.name). Scans and form fills are scoped to this member."
    }

    func clearActiveProfile() {
        activeProfile = nil
    }

    func applyManualOverride(fieldId: String, newValue: String) {
        guard let index = extractedFields.firstIndex(where: { $0.id == fieldId }) else { return }
        extractedFields[index].value = newValue
        extractedFields[index].isManualOverride = true
    }

    func extractAllFields(_ fields: [WebFormField]) {
        guard let profile = activeProfile else {
            statusMessage = "Select a household member on the wheel before filling a form."
            return
        }

        isExtracting = true
        statusMessage = "Extracting fields for \(profile.name)…"

        Task {
            var results: [FieldExtractionResult] = []
            for field in fields {
                do {
                    let result = try await ExtractFieldService.extractField(
                        field: field,
                        profile: profile,
                        database: database
                    )
                    results.append(result)
                } catch {
                    results.append(
                        FieldExtractionResult(
                            fieldId: field.id,
                            fieldLabel: field.label,
                            value: "",
                            sourceDocumentName: "Error",
                            sourceFilePath: "",
                            candidates: [],
                            isManualOverride: false
                        )
                    )
                }
            }
            extractedFields = results
            isExtracting = false
            statusMessage = "Ready to apply \(results.count) field(s) with evidence badges."
        }
    }
}
