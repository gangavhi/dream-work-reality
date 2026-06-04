import Foundation

/// Document-agnostic field extraction from layout label→value pairs (any upload, any document type).
enum OpenVocabularyFieldExtractor {
    static func suggestions(
        from layout: LayoutIntelligenceAgent.LayoutDocument,
        documentTypeHint: String? = nil
    ) -> [OcrFieldSuggestion] {
        var out: [OcrFieldSuggestion] = []

        for pair in layout.labelValuePairs {
            if let suggestion = suggestion(forLabel: pair.label, value: pair.value, documentTypeHint: documentTypeHint) {
                out.append(suggestion)
            }
        }

        for line in layout.layoutText.components(separatedBy: .newlines) {
            guard let inline = OcrLayoutSerializer.inlineLabelValue(from: line) else { continue }
            if let suggestion = suggestion(forLabel: inline.label, value: inline.value, documentTypeHint: documentTypeHint) {
                out.append(suggestion)
            }
        }

        return dedupe(out)
    }

    private static func suggestion(
        forLabel label: String,
        value: String,
        documentTypeHint: String?
    ) -> OcrFieldSuggestion? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        guard let resolved = SemanticFieldLabelMapper.resolve(
            label: label,
            documentTypeHint: documentTypeHint
        ) else { return nil }

        guard MappedFieldValueValidator.accepts(profileKey: resolved.profileKey, value: trimmedValue) else {
            return nil
        }

        let score = resolved.isExtension ? 0.72 : 0.8
        return OcrFieldSuggestion(
            profileKey: resolved.profileKey,
            label: resolved.displayLabel,
            value: trimmedValue,
            confidence: resolved.isExtension ? "Medium" : "High",
            confidenceScore: score,
            mappingSource: .onDevice
        )
    }

    private static func dedupe(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for item in suggestions {
            if let existing = byKey[item.profileKey] {
                if item.confidenceScore > existing.confidenceScore {
                    byKey[item.profileKey] = item
                }
            } else {
                byKey[item.profileKey] = item
            }
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }
}
