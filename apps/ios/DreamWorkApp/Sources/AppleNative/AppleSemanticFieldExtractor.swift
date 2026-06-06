import Foundation

/// NL-based field extraction from layout pairs (replaces ONNX / GGUF field paths).
enum AppleSemanticFieldExtractor {
    static func suggestions(
        from layout: LayoutIntelligenceAgent.LayoutDocument,
        documentTypeHint: String?
    ) -> [OcrFieldSuggestion] {
        var out = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: documentTypeHint
        )
        if out.count < 4 {
            let heuristic = UniversalDocumentParser.parse(from: layout.layoutText)
            out = mergePreferHigherConfidence(out, heuristic)
        }
        return out
    }

    private static func mergePreferHigherConfidence(
        _ a: [OcrFieldSuggestion],
        _ b: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        var byKey = Dictionary(uniqueKeysWithValues: a.map { ($0.profileKey, $0) })
        for item in b {
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
