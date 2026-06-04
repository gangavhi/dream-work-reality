import Foundation
import NaturalLanguage

/// Maps OCR label text to canonical profile keys using NLEmbedding (on-device, no ONNX).
enum NLFieldLabelMapper {
    private static let embedding: NLEmbedding? = {
        NLEmbedding.wordEmbedding(for: .english)
    }()

    static func profileKey(
        forLabel label: String,
        documentType: ScannedDocumentType,
        schemaKeys: [String]
    ) -> String? {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if let direct = directMatch(normalized, schemaKeys: schemaKeys) {
            return direct
        }

        guard let embedding else {
            return keywordFallback(normalized, documentType: documentType)
        }

        var bestKey: String?
        var bestScore: Double = 0.42

        for key in schemaKeys {
            let def = ProfileSchema.definition(for: key)
            let candidates = [
                key.replacingOccurrences(of: "_", with: " "),
                def?.label.lowercased() ?? "",
            ].filter { !$0.isEmpty }

            for candidate in candidates {
                let score = embedding.distance(between: normalized, and: candidate)
                guard score < bestScore else { continue }
                bestScore = score
                bestKey = key
            }
        }

        return bestKey ?? keywordFallback(normalized, documentType: documentType)
    }

    private static func directMatch(_ label: String, schemaKeys: [String]) -> String? {
        let slug = label
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        if schemaKeys.contains(slug) { return slug }
        for key in schemaKeys {
            if let def = ProfileSchema.definition(for: key),
               def.label.lowercased() == label
            {
                return key
            }
        }
        return nil
    }

    private static func keywordFallback(_ label: String, documentType: ScannedDocumentType) -> String? {
        _ = documentType
        for field in ProfileSchema.allFields {
            let defLabel = field.label.lowercased()
            if label.contains(defLabel) || defLabel.contains(label) {
                return field.key
            }
        }
        if label.contains("dob") || label.contains("birth") { return ProfileFieldKey.dateOfBirth }
        if label.contains("expir") { return ProfileFieldKey.driversLicenseExpiry }
        if label.contains("license") && label.contains("number") { return ProfileFieldKey.driversLicenseNumber }
        return nil
    }
}
