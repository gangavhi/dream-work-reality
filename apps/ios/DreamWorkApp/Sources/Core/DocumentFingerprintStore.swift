import CryptoKit
import Foundation

/// Links a prior document import to the profile it was saved on (for silent re-import updates).
struct PreviousDocumentImport: Hashable {
    let fingerprint: String
    let personID: String?
    let personName: String?
    let savedAt: Date
}

/// Tracks document OCR fingerprints so repeat imports update the same profile instead of warning.
enum DocumentFingerprintStore {
    private static let storageKey = "dreamwork.document.fingerprints"

    private struct StoredFingerprint: Codable {
        var fingerprint: String
        var personID: String?
        var personName: String?
        var savedAt: Date
    }

    static func fingerprint(for ocrText: String) -> String {
        let normalized = ocrText
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func findPreviousImport(for ocrText: String) -> PreviousDocumentImport? {
        let fp = fingerprint(for: ocrText)
        guard let stored = load()[fp] else { return nil }
        return PreviousDocumentImport(
            fingerprint: fp,
            personID: stored.personID,
            personName: stored.personName,
            savedAt: stored.savedAt
        )
    }

    static func record(ocrText: String, personID: String, personName: String?) {
        let fp = fingerprint(for: ocrText)
        var all = load()
        all[fp] = StoredFingerprint(
            fingerprint: fp,
            personID: personID,
            personName: personName,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Removes stored document fingerprints when a profile is deleted.
    static func removeEntries(forPersonID personID: String, personName: String? = nil) {
        var all = load()
        let normalizedName = personName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        all = all.filter { _, stored in
            if stored.personID == personID { return false }
            if let normalizedName,
               let storedName = stored.personName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               storedName == normalizedName
            {
                return false
            }
            return true
        }

        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func load() -> [String: StoredFingerprint] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: StoredFingerprint].self, from: data)
        else { return [:] }
        return decoded
    }
}
