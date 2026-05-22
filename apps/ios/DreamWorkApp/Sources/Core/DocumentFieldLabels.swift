import Foundation

/// Region and document context for human-readable field labels that match the source document.
struct DocumentFieldLabelContext: Hashable {
    var documentType: ScannedDocumentType
    var issuerRegion: String?
    var country: String?

    static func from(
        scan: DriverLicenseScanResult,
        documentType: ScannedDocumentType = .driversLicense
    ) -> DocumentFieldLabelContext {
        var values: [String: String] = [:]
        if let state = scan.state { values[ProfileFieldKey.driversLicenseState] = state }
        if let country = scan.genAIValues?["country"] { values[ProfileFieldKey.country] = country }
        return from(fieldValues: values, documentType: documentType)
    }

    static func from(
        person: PersonRecord,
        documentType: ScannedDocumentType = .driversLicense
    ) -> DocumentFieldLabelContext {
        var values: [String: String] = [:]
        for field in person.fields where !field.value.isEmpty {
            values[field.key] = field.value
        }
        return from(fieldValues: values, documentType: documentType)
    }

    static func from(
        fieldValues: [String: String],
        documentType: ScannedDocumentType
    ) -> DocumentFieldLabelContext {
        let region = normalizedRegion(
            fieldValues[ProfileFieldKey.driversLicenseState]
                ?? fieldValues[ProfileFieldKey.state]
                ?? fieldValues[ProfileFieldKey.passportCountry]
        )
        let country = normalizedCountry(
            fieldValues[ProfileFieldKey.country]
                ?? fieldValues[ProfileFieldKey.passportCountry],
            region: region
        )
        return DocumentFieldLabelContext(
            documentType: documentType,
            issuerRegion: region,
            country: country
        )
    }

    static func from(
        suggestions: [OcrFieldSuggestion],
        documentType: ScannedDocumentType
    ) -> DocumentFieldLabelContext {
        let values = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        return from(fieldValues: values, documentType: documentType)
    }

    private static func normalizedRegion(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count == 2, trimmed.range(of: #"^[A-Za-z]{2}$"#, options: .regularExpression) != nil {
            return trimmed.uppercased()
        }
        return trimmed
    }

    private static func normalizedCountry(_ raw: String?, region: String?) -> String? {
        if let raw {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.uppercased()
            }
        }
        if let region, ScanFieldValidator.isPlausibleUSState(region) {
            return "US"
        }
        return nil
    }
}

/// Card-accurate labels for government ID fields by US state, country, and document type.
enum DocumentFieldLabels {
    static func label(for profileKey: String, context: DocumentFieldLabelContext) -> String {
        if let contextual = contextualLabel(for: profileKey, context: context) {
            return contextual
        }
        return ProfileSchema.definition(for: profileKey)?.label ?? ProfileSchema.label(forExtensionKey: profileKey)
    }

    static func relabel(
        _ suggestions: [OcrFieldSuggestion],
        context: DocumentFieldLabelContext
    ) -> [OcrFieldSuggestion] {
        suggestions.map { suggestion in
            OcrFieldSuggestion(
                profileKey: suggestion.profileKey,
                label: label(for: suggestion.profileKey, context: context),
                value: suggestion.value,
                confidence: suggestion.confidence,
                confidenceScore: suggestion.confidenceScore
            )
        }
    }

    private static func contextualLabel(
        for profileKey: String,
        context: DocumentFieldLabelContext
    ) -> String? {
        switch profileKey {
        case ProfileFieldKey.driversLicenseNumber:
            return driverLicenseNumberLabel(context: context)
        case ProfileFieldKey.driversLicenseIssueDate:
            return driverLicenseIssueDateLabel(context: context)
        case ProfileFieldKey.driversLicenseExpiry:
            return driverLicenseExpiryLabel(context: context)
        case ProfileFieldKey.driversLicenseState:
            return issuingRegionLabel(context: context)
        case ProfileFieldKey.stateIdNumber:
            return stateIdNumberLabel(context: context)
        case ProfileFieldKey.passportNumber:
            return passportNumberLabel(context: context)
        default:
            return nil
        }
    }

    // MARK: - US driver's license number (field 4d on AAMVA cards)

    private static let usDriverLicenseNumberByState: [String: String] = [
        "TX": "Driver License No",
        "CA": "DL No",
        "NY": "ID No",
        "NJ": "ID No",
        "FL": "DL No",
        "IL": "DL No",
        "PA": "DL No",
        "OH": "DL No",
        "GA": "DL No",
        "NC": "DL No",
        "MI": "DL No",
        "VA": "Customer No",
        "WA": "License No",
        "AZ": "DL No",
        "MA": "DL No",
        "TN": "DL No",
        "IN": "DL No",
        "MO": "DL No",
        "MD": "DL No",
        "WI": "DL No",
        "CO": "DL No",
        "MN": "DL No",
        "SC": "DL No",
        "AL": "DL No",
        "LA": "DL No",
        "KY": "DL No",
        "OR": "DL No",
        "OK": "DL No",
        "CT": "DL No",
        "UT": "DL No",
        "IA": "DL No",
        "NV": "DL No",
        "AR": "DL No",
        "MS": "DL No",
        "KS": "DL No",
        "NM": "DL No",
        "NE": "DL No",
        "WV": "DL No",
        "ID": "DL No",
        "HI": "DL No",
        "NH": "DL No",
        "ME": "DL No",
        "RI": "DL No",
        "MT": "DL No",
        "DE": "DL No",
        "SD": "DL No",
        "ND": "DL No",
        "AK": "DL No",
        "DC": "DL No",
        "VT": "DL No",
        "WY": "DL No",
    ]

    private static let countryDriverLicenseNumber: [String: String] = [
        "US": "Driver License No",
        "GB": "Driving Licence No",
        "UK": "Driving Licence No",
        "CA": "Licence No",
        "AU": "Licence No",
        "NZ": "Licence No",
        "IN": "DL No",
        "DE": "Führerschein-Nr.",
        "FR": "N° permis",
        "MX": "No. licencia",
        "BR": "CNH No",
        "JP": "Licence No",
        "KR": "Licence No",
        "SG": "Licence No",
        "AE": "Licence No",
        "IE": "Licence No",
        "ZA": "Licence No",
    ]

    private static func driverLicenseNumberLabel(context: DocumentFieldLabelContext) -> String {
        guard context.documentType == .driversLicense || context.documentType == .stateId else {
            return "Driver License No"
        }
        if let region = context.issuerRegion,
           let label = usDriverLicenseNumberByState[region.uppercased()]
        {
            return label
        }
        if let country = context.country?.uppercased(),
           let label = countryDriverLicenseNumber[country]
        {
            return label
        }
        if context.country?.uppercased() == "US" || context.issuerRegion != nil {
            return "Driver License No"
        }
        return "Driving Licence No"
    }

    // MARK: - Issue / expiry

    private static let countryIssueDate: [String: String] = [
        "GB": "Valid from",
        "UK": "Valid from",
        "AU": "Issue date",
        "CA": "Issue date",
        "IN": "Issue date",
    ]

    private static let countryExpiryDate: [String: String] = [
        "GB": "Valid to",
        "UK": "Valid to",
        "AU": "Expiry date",
        "CA": "Expiry date",
        "IN": "Expiry date",
    ]

    private static func driverLicenseIssueDateLabel(context: DocumentFieldLabelContext) -> String {
        if context.documentType == .driversLicense,
           context.country?.uppercased() == "US" || context.issuerRegion != nil
        {
            return "Issue Date"
        }
        if let country = context.country?.uppercased(),
           let label = countryIssueDate[country]
        {
            return label
        }
        return "Issue date"
    }

    private static func driverLicenseExpiryLabel(context: DocumentFieldLabelContext) -> String {
        if context.documentType == .driversLicense,
           context.country?.uppercased() == "US" || context.issuerRegion != nil
        {
            return "Expiry Date"
        }
        if let country = context.country?.uppercased(),
           let label = countryExpiryDate[country]
        {
            return label
        }
        return "Expiry date"
    }

    private static func issuingRegionLabel(context: DocumentFieldLabelContext) -> String {
        switch context.documentType {
        case .driversLicense:
            if context.country?.uppercased() == "US" || context.issuerRegion != nil {
                return "Issuing state"
            }
            return "Issuing region"
        case .passport:
            return "Passport country"
        default:
            return "Issuing region"
        }
    }

    private static func stateIdNumberLabel(context: DocumentFieldLabelContext) -> String {
        if context.issuerRegion == "TX" { return "ID No" }
        if context.country?.uppercased() == "US" || context.issuerRegion != nil { return "State ID No" }
        return "ID No"
    }

    private static func passportNumberLabel(context: DocumentFieldLabelContext) -> String {
        switch context.country?.uppercased() {
        case "US", "GB", "UK", "CA", "AU", "IN":
            return "Passport No"
        default:
            return "Passport number"
        }
    }
}

extension ProfileSchema {
    static func contextualLabel(for key: String, context: DocumentFieldLabelContext) -> String {
        DocumentFieldLabels.label(for: key, context: context)
    }
}
