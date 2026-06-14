import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct SynthesizedField {
    @Guide(description: "Best value for the requested form field")
    var value: String
    @Guide(description: "Document name used as evidence")
    var sourceDocument: String
}
#endif

/// Local on-device synthesis via Apple Foundation Models (iOS 26+).
enum FieldSynthesizer {
    static func synthesize(
        fieldLabel: String,
        candidates: [SearchCandidate]
    ) async throws -> (value: String, sourceDocumentName: String, sourceFilePath: String) {
        guard let top = candidates.first else {
            return ("", "No source", "")
        }

        if candidates.count > 1, hasConflict(candidates) {
            // Conflict handling: caller presents all candidates; do not guess.
            return ("", top.documentType ?? URL(fileURLWithPath: top.filePath).lastPathComponent, top.filePath)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await foundationModelSynthesis(fieldLabel: fieldLabel, candidates: candidates)
        }
        #endif

        return heuristicSynthesis(fieldLabel: fieldLabel, candidates: candidates)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func foundationModelSynthesis(
        fieldLabel: String,
        candidates: [SearchCandidate]
    ) async throws -> (value: String, sourceDocumentName: String, sourceFilePath: String) {
        let context = candidates
            .map { "- \($0.documentType ?? "document"): \($0.excerpt)" }
            .joined(separator: "\n")

        let session = LanguageModelSession()
        let response = try await session.respond(
            to: """
            Extract the value for form field '\(fieldLabel)' from the household evidence below.
            Use only the evidence. If uncertain, return an empty value.
            Evidence:
            \(context)
            """,
            generating: SynthesizedField.self
        )

        let sourcePath = candidates.first?.filePath ?? ""
        return (
            response.content.value,
            response.content.sourceDocument,
            sourcePath
        )
    }
    #endif

    private static func heuristicSynthesis(
        fieldLabel: String,
        candidates: [SearchCandidate]
    ) -> (value: String, sourceDocumentName: String, sourceFilePath: String) {
        let label = fieldLabel.lowercased()
        for candidate in candidates {
            let lines = candidate.excerpt.components(separatedBy: .newlines)
            for line in lines {
                let lower = line.lowercased()
                if lower.contains(label) {
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        return (
                            parts[1].trimmingCharacters(in: .whitespaces),
                            candidate.documentType ?? URL(fileURLWithPath: candidate.filePath).lastPathComponent,
                            candidate.filePath
                        )
                    }
                }
            }
        }

        let top = candidates[0]
        return (
            top.excerpt.components(separatedBy: .newlines).first ?? "",
            top.documentType ?? URL(fileURLWithPath: top.filePath).lastPathComponent,
            top.filePath
        )
    }

    private static func hasConflict(_ candidates: [SearchCandidate]) -> Bool {
        let values = Set(candidates.prefix(3).map { $0.excerpt.prefix(80) })
        return values.count > 1
    }
}
