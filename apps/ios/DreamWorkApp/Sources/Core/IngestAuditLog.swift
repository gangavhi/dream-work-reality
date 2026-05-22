import Foundation

struct IngestAuditEntry: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let documentType: String
    let personID: String?
    let personName: String?
    let fieldCount: Int
    let ocrEngine: String
    let usedAI: Bool
    let notes: String
}

/// On-device audit trail for document ingest apply actions.
enum IngestAuditLog {
    private static let storageKey = "dreamwork.ingest.audit_log"
    private static let maxEntries = 200

    static func append(
        documentType: String,
        personID: String?,
        personName: String?,
        fieldCount: Int,
        usedAI: Bool,
        notes: String = ""
    ) {
        var entries = load()
        entries.insert(
            IngestAuditEntry(
                id: UUID().uuidString,
                timestamp: Date(),
                documentType: documentType,
                personID: personID,
                personName: personName,
                fieldCount: fieldCount,
                ocrEngine: "vision.en.v1",
                usedAI: usedAI,
                notes: notes
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func load() -> [IngestAuditEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([IngestAuditEntry].self, from: data)
        else { return [] }
        return entries
    }
}
