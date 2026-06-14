import Foundation

/// ExtractField service: Query -> Hybrid Search -> Local LLM Synthesis.
enum ExtractFieldService {
    static func extractField(
        field: WebFormField,
        profile: Profile,
        database: TrustNestDatabase
    ) async throws -> FieldExtractionResult {
        let candidates = try await HybridSearchOrchestrator.search(
            query: field.label,
            householdId: profile.householdId,
            individualId: profile.individualId,
            database: database,
            limit: 5
        )

        if candidates.count > 1, conflicting(candidates) {
            return FieldExtractionResult(
                fieldId: field.id,
                fieldLabel: field.label,
                value: "",
                sourceDocumentName: "Multiple sources",
                sourceFilePath: candidates.first?.filePath ?? "",
                candidates: candidates,
                isManualOverride: false
            )
        }

        let synthesis = try await FieldSynthesizer.synthesize(
            fieldLabel: field.label,
            candidates: candidates
        )

        return FieldExtractionResult(
            fieldId: field.id,
            fieldLabel: field.label,
            value: synthesis.value,
            sourceDocumentName: synthesis.sourceDocumentName,
            sourceFilePath: synthesis.sourceFilePath,
            candidates: candidates,
            isManualOverride: false
        )
    }

    private static func conflicting(_ candidates: [SearchCandidate]) -> Bool {
        let distances = candidates.map(\.distance)
        guard let first = distances.first else { return false }
        return distances.contains { abs($0 - first) > 0.15 }
    }
}
