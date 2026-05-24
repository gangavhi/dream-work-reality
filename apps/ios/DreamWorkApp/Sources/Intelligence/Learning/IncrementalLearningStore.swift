import Foundation

/// Stores user-confirmed field corrections for future pattern hints (incremental learning slot).
enum IncrementalLearningStore {
    struct Correction: Codable, Hashable {
        var profileKey: String
        var originalValue: String
        var correctedValue: String
        var documentType: String
        var recordedAt: Date
    }

    private static let storageKey = "dreamwork.learning.corrections.v1"

    static func record(
        profileKey: String,
        originalValue: String,
        correctedValue: String,
        documentType: String
    ) {
        let trimmedOriginal = originalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrected = correctedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCorrected.isEmpty, trimmedOriginal != trimmedCorrected else { return }

        var items = load()
        items.insert(
            Correction(
                profileKey: profileKey,
                originalValue: trimmedOriginal,
                correctedValue: trimmedCorrected,
                documentType: documentType,
                recordedAt: Date()
            ),
            at: 0
        )
        if items.count > 200 { items = Array(items.prefix(200)) }
        save(items)
    }

    static func hints(for profileKey: String, documentType: String) -> [String] {
        load()
            .filter { $0.profileKey == profileKey && $0.documentType == documentType }
            .prefix(5)
            .map(\.correctedValue)
    }

    private static func load() -> [Correction] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Correction].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ items: [Correction]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
