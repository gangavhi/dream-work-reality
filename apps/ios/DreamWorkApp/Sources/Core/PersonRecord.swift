import Foundation

/// Mirrors JSON from `dreamwork_manual_entries_json` (`ManualEntry` in Rust).
struct PersonRecord: Identifiable, Codable, Hashable {
    struct Field: Codable, Hashable {
        let key: String
        let value: String
    }

    let id: String
    let fields: [Field]

    var displayTitle: String {
        let name = value(for: ProfileFieldKey.displayName)
        return name.isEmpty ? id : name
    }

    func value(for key: String) -> String {
        fields.first { $0.key == key }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func withValue(_ value: String, for key: String) -> PersonRecord {
        var updated = fields.filter { $0.key != key }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            updated.append(Field(key: key, value: trimmed))
        }
        updated.sort { $0.key < $1.key }
        return PersonRecord(id: id, fields: updated)
    }

    func merged(with updates: [String: String]) -> PersonRecord {
        updates.reduce(self) { partial, pair in
            partial.withValue(pair.value, for: pair.key)
        }
    }

    static func newID() -> String {
        "person-\(UUID().uuidString.lowercased())"
    }

    static func empty(id: String = PersonRecord.newID()) -> PersonRecord {
        PersonRecord(id: id, fields: [])
    }
}
