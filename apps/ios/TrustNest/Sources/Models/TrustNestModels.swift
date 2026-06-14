import Foundation

enum RelationshipType: String, CaseIterable, Codable, Sendable {
    case primary = "Primary"
    case spouse = "Spouse"
    case dependent = "Dependent"
}

/// Maps to `profiles` table — one row per household member (UI circle).
struct Profile: Identifiable, Codable, Equatable, Sendable {
    var individualId: String
    var householdId: String
    var name: String
    var relationshipType: RelationshipType

    var id: String { individualId }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Maps to `documents` table.
struct HouseholdDocument: Identifiable, Codable, Equatable, Sendable {
    var docId: String
    var individualId: String
    var householdId: String
    var documentType: String?
    var filePath: String

    var id: String { docId }
}

struct DocumentChunk: Sendable {
    let text: String
    let filePath: String
}

struct SearchCandidate: Identifiable, Equatable, Sendable {
    let docId: String
    let filePath: String
    let documentType: String?
    let distance: Double
    let excerpt: String

    var id: String { docId }
}

struct FieldExtractionResult: Identifiable, Equatable, Sendable {
    let fieldId: String
    let fieldLabel: String
    var value: String
    var sourceDocumentName: String
    var sourceFilePath: String
    var candidates: [SearchCandidate]
    var isManualOverride: Bool

    var id: String { fieldId }
}

struct WebFormField: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let name: String
    let inputType: String
}
