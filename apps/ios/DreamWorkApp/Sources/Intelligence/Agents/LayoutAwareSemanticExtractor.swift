import Foundation

/// Local "LLM extraction" facade: chunks layout text, carries nearby context, and runs the
/// on-device mapper per chunk. When a GGUF/CoreML model is bundled, this remains the call site.
enum LayoutAwareSemanticExtractor {
    struct Chunk: Hashable {
        let index: Int
        let text: String
        let context: String
    }

    static func extract(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        classification: ClassificationAgent.Result,
        schemaKeys: [String]
    ) -> [OcrFieldSuggestion] {
        let chunks = makeChunks(
            from: layout.modelInput.isEmpty ? layout.layoutText : layout.modelInput,
            documentType: classification.openDocumentType
        )
        guard !chunks.isEmpty else { return [] }

        var out: [OcrFieldSuggestion] = []
        for chunk in chunks {
            let prompt = [
                "## Document type",
                classification.openDocumentType ?? "unknown",
                "",
                "## Retrieved context",
                chunk.context,
                "",
                "## Layout chunk \(chunk.index + 1)",
                chunk.text,
            ].joined(separator: "\n")

            guard let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: prompt,
                profileSchemaKeys: schemaKeys
            ) else { continue }
            out.append(contentsOf: mapped.suggestions.map { suggestion in
                OcrFieldSuggestion(
                    profileKey: suggestion.profileKey,
                    label: suggestion.label,
                    value: suggestion.value,
                    confidence: suggestion.confidence,
                    confidenceScore: min(0.84, suggestion.confidenceScore),
                    mappingSource: .onDevice
                )
            })
        }
        return dedupe(out)
    }

    static func makeChunks(
        from text: String,
        documentType: String?,
        maxCharacters: Int = 3_000
    ) -> [Chunk] {
        let lines = text.components(separatedBy: .newlines)
        var chunks: [String] = []
        var current: [String] = []
        var count = 0

        for line in lines {
            let nextCount = count + line.count + 1
            if nextCount > maxCharacters, !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = []
                count = 0
            }
            current.append(line)
            count += line.count + 1
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }

        let retrievalContext = VectorDocumentMemory.search(
            query: [documentType ?? "", String(text.prefix(500))].joined(separator: " ")
        )
        .prefix(3)
        .map { "\($0.documentType): \($0.snippet)" }
        .joined(separator: "\n---\n")

        return chunks.enumerated().map { index, chunk in
            Chunk(index: index, text: chunk, context: retrievalContext)
        }
    }

    private static func dedupe(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for suggestion in suggestions {
            if let existing = byKey[suggestion.profileKey],
               existing.confidenceScore >= suggestion.confidenceScore
            {
                continue
            }
            byKey[suggestion.profileKey] = suggestion
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }
}
