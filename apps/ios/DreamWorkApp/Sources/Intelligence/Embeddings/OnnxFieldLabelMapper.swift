import Foundation

/// Label → profile_key mapping via MiniLM ONNX cosine similarity against canonical phrases.
enum OnnxFieldLabelMapper {
    private struct PhraseEntry {
        let profileKey: String
        let embedding: [Float]
    }

    private static let lock = NSLock()
    private static var phraseIndex: [PhraseEntry]?
    private static let similarityThreshold = 0.52

    static func canonicalKey(for label: String) -> String? {
        guard MiniLMOnnxFieldEmbedder.shared.isAvailable,
              let query = MiniLMOnnxFieldEmbedder.shared.embed(label)
        else { return nil }

        let index = loadPhraseIndex()
        var best: (key: String, score: Double)?
        for entry in index {
            let score = MiniLMOnnxFieldEmbedder.shared.cosineSimilarity(query, entry.embedding)
            if score >= similarityThreshold, best == nil || score > best!.score {
                best = (entry.profileKey, score)
            }
        }
        return best?.key
    }

    static func runtimeStatus() -> String {
        MiniLMOnnxFieldEmbedder.shared.statusToken
    }

    // MARK: - Index

    private static func loadPhraseIndex() -> [PhraseEntry] {
        lock.lock()
        defer { lock.unlock() }
        if let phraseIndex { return phraseIndex }

        var entries: [PhraseEntry] = []
        let embedder = MiniLMOnnxFieldEmbedder.shared
        for group in SemanticFieldLabelMapper.synonymGroupsForEmbedding {
            for phrase in group.phrases {
                guard let vector = embedder.embed(phrase) else { continue }
                entries.append(PhraseEntry(profileKey: group.profileKey, embedding: vector))
            }
        }
        for definition in ProfileSchema.allFields {
            guard let vector = embedder.embed(definition.label.lowercased()) else { continue }
            entries.append(PhraseEntry(profileKey: definition.key, embedding: vector))
        }

        phraseIndex = entries
        return entries
    }
}
