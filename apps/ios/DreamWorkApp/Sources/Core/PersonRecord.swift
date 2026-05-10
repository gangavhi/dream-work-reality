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
        let name = fields.first { $0.key == "display_name" }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? id : name
    }
}
