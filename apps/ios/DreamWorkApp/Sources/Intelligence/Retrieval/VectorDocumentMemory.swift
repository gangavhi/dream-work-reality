import Foundation

/// Local document memory for semantic retrieval (vector DB slot — Qdrant/LanceDB TBD).
enum VectorDocumentMemory {
    struct Entry: Codable, Hashable, Identifiable {
        var id: String
        var documentType: String
        var snippet: String
        var ingestedAt: Date
        var tokenSignature: [String]
    }

    private static let storageKey = "dreamwork.vector_memory.v1"

    static func index(documentType: String, plainText: String, maxSnippet: Int = 400) {
        let snippet = String(plainText.prefix(maxSnippet))
        let entry = Entry(
            id: UUID().uuidString,
            documentType: documentType,
            snippet: snippet,
            ingestedAt: Date(),
            tokenSignature: tokens(from: plainText)
        )
        var entries = load()
        entries.insert(entry, at: 0)
        if entries.count > 48 { entries = Array(entries.prefix(48)) }
        save(entries)
    }

    static func search(query: String, limit: Int = 8) -> [Entry] {
        let qTokens = Set(tokens(from: query))
        guard !qTokens.isEmpty else { return [] }
        return load()
            .map { entry -> (Entry, Double) in
                let eTokens = Set(entry.tokenSignature)
                let overlap = Double(qTokens.intersection(eTokens).count) / Double(qTokens.count)
                return (entry, overlap)
            }
            .filter { $0.1 > 0.15 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private static func tokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
