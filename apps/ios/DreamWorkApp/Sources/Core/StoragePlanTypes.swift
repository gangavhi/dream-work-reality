import Foundation

enum StorageOperationKind: String, Codable, Hashable {
    case upsertManualField = "upsert_manual_field"
    case upsertExtensionField = "upsert_extension_field"
}

struct StorageOperationSuggestion: Identifiable, Hashable {
    let kind: StorageOperationKind
    let personID: String?
    let key: String
    let value: String
    let reason: String

    var id: String { "\(kind.rawValue)-\(key)" }

    var targetLabel: String {
        switch kind {
        case .upsertManualField: return "Profile field"
        case .upsertExtensionField: return "Extension field"
        }
    }
}

struct StoragePlanSummary: Hashable {
    let canonicalCount: Int
    let extensionCount: Int
    let skippedEmpty: Int
}

struct StoragePlanSuggestion: Hashable {
    let operations: [StorageOperationSuggestion]
    let summary: StoragePlanSummary
}
