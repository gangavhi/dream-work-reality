import Foundation

/// Household entity types for the on-device knowledge graph (SQLite-backed over time).
enum KnowledgeEntityType: String, CaseIterable, Hashable {
    case identity
    case address
    case vehicle
    case insurance
    case employment
    case financial
    case medical
    case document
}

struct KnowledgeEntity: Hashable, Identifiable {
    let id: String
    let type: KnowledgeEntityType
    let profileKey: String
    let value: String
    let sourceDocumentType: String?
}

struct SmartAutofillField: Hashable, Identifiable {
    let profileKey: String
    let label: String
    let value: String
    let entityType: KnowledgeEntityType?
    let confidenceScore: Double
    let requiresManualConfirmation: Bool

    var id: String { profileKey }
}

struct SmartAutofillPayload: Hashable {
    let documentType: String
    let canonicalIdentity: CanonicalIdentityProfile
    let fields: [SmartAutofillField]

    var fieldMap: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.profileKey, $0.value) })
    }
}

struct StructuredIdentityGraph: Hashable {
    let entities: [KnowledgeEntity]
    let autofillPayload: SmartAutofillPayload
}

/// Links extracted profile fields to graph entity types for cross-document queries.
enum DocumentKnowledgeGraph {
    private static let keyToEntity: [String: KnowledgeEntityType] = [
        ProfileFieldKey.displayName: .identity,
        ProfileFieldKey.legalFirstName: .identity,
        ProfileFieldKey.legalLastName: .identity,
        ProfileFieldKey.dateOfBirth: .identity,
        ProfileFieldKey.ssn: .identity,
        ProfileFieldKey.passportNumber: .identity,
        ProfileFieldKey.driversLicenseNumber: .identity,
        ProfileFieldKey.addressLine1: .address,
        ProfileFieldKey.city: .address,
        ProfileFieldKey.state: .address,
        ProfileFieldKey.postalCode: .address,
        ProfileFieldKey.insuranceMemberId: .insurance,
        ProfileFieldKey.insuranceCarrier: .insurance,
        ProfileFieldKey.employerName: .employment,
        ProfileFieldKey.bankName: .financial,
        ProfileFieldKey.bankAccountLast4: .financial,
        "vehicle_vin": .vehicle,
        "aadhaar_number": .identity,
        "pan_number": .identity,
    ]

    static func entities(
        from suggestions: [OcrFieldSuggestion],
        documentType: String
    ) -> [KnowledgeEntity] {
        suggestions.compactMap { suggestion in
            guard let entityType = keyToEntity[suggestion.profileKey] ?? extensionEntityType(suggestion.profileKey)
            else { return nil }
            return KnowledgeEntity(
                id: "\(entityType.rawValue).\(suggestion.profileKey)",
                type: entityType,
                profileKey: suggestion.profileKey,
                value: suggestion.value,
                sourceDocumentType: documentType
            )
        }
    }

    static func entityType(forProfileKey key: String) -> KnowledgeEntityType? {
        keyToEntity[key] ?? extensionEntityType(key)
    }

    static func buildIdentityGraph(
        from suggestions: [OcrFieldSuggestion],
        documentType: String
    ) -> StructuredIdentityGraph {
        let entities = entities(from: suggestions, documentType: documentType)
        let byKey = Dictionary(uniqueKeysWithValues: entities.map { ($0.profileKey, $0.type) })
        let autofillFields = ProfileSchema.sortSuggestions(suggestions).map { suggestion in
            SmartAutofillField(
                profileKey: suggestion.profileKey,
                label: suggestion.label,
                value: suggestion.value,
                entityType: byKey[suggestion.profileKey] ?? entityType(forProfileKey: suggestion.profileKey),
                confidenceScore: suggestion.confidenceScore,
                requiresManualConfirmation: suggestion.requiresManualConfirmation
            )
        }
        return StructuredIdentityGraph(
            entities: entities,
            autofillPayload: SmartAutofillPayload(
                documentType: documentType,
                canonicalIdentity: CanonicalIdentityProfile.from(suggestions: suggestions),
                fields: autofillFields
            )
        )
    }

    private static func extensionEntityType(_ key: String) -> KnowledgeEntityType? {
        if key.contains("insurance") { return .insurance }
        if key.contains("employ") || key.contains("job") { return .employment }
        if key.contains("bank") || key.contains("account") { return .financial }
        if key.contains("vehicle") || key.contains("vin") { return .vehicle }
        if key.contains("medical") || key.contains("patient") { return .medical }
        return nil
    }
}
