import Foundation

/// Canonical profile field keys stored in SQLite via Rust `manual_field`.
enum ProfileFieldKey {
    static let displayName = "display_name"
    static let relationship = "relationship"
    static let legalFirstName = "legal_first_name"
    static let legalLastName = "legal_last_name"
    static let legalMiddleName = "legal_middle_name"
    static let dateOfBirth = "date_of_birth"
    static let email = "email"
    static let phoneMobile = "phone_mobile"
    static let phoneHome = "phone_home"
    static let addressLine1 = "address_line1"
    static let addressLine2 = "address_line2"
    static let city = "city"
    static let state = "state"
    static let postalCode = "postal_code"
    static let country = "country"
    static let ssn = "ssn"
    static let filingStatus = "filing_status"
    static let driversLicenseNumber = "drivers_license_number"
    static let driversLicenseState = "drivers_license_state"
    static let driversLicenseIssueDate = "drivers_license_issue_date"
    static let driversLicenseExpiry = "drivers_license_expiry"
    static let passportNumber = "passport_number"
    static let passportCountry = "passport_country"
    static let passportIssueDate = "passport_issue_date"
    static let passportIssuedPlace = "passport_issued_place"
    static let passportAddress = "passport_address"
    static let passportExpiry = "passport_expiry"
    static let insuranceCarrier = "insurance_carrier"
    static let insuranceMemberId = "insurance_member_id"
    static let emergencyContactName = "emergency_contact_name"
    static let emergencyContactPhone = "emergency_contact_phone"
    static let gender = "gender"
    static let stateIdNumber = "state_id_number"
    static let stateIdExpiry = "state_id_expiry"
    static let employerName = "employer_name"
    static let bankName = "bank_name"
    static let bankAccountLast4 = "bank_account_last4"
    static let utilityProvider = "utility_provider"
    static let taxFormType = "tax_form_type"
    static let taxYear = "tax_year"
}

struct ProfileFieldDefinition: Identifiable, Hashable {
    let key: String
    let label: String
    let section: ProfileSection
    let isSensitive: Bool

    var id: String { key }
}

enum ProfileSection: String, CaseIterable, Identifiable {
    case identity = "Identity"
    case contact = "Contact"
    case address = "Address"
    case governmentIds = "Government IDs"
    case tax = "Tax"
    case medical = "Medical"

    var id: String { rawValue }
}

enum HouseholdRelationship: String, CaseIterable, Identifiable {
    case selfMember = "Self"
    case spouse = "Spouse / Partner"
    case child = "Child"
    case parent = "Parent"
    case other = "Other"

    var id: String { rawValue }
}

enum ScannedDocumentType: String, CaseIterable, Identifiable {
    case driversLicense = "Driver's license"
    case passport = "Passport"
    case stateId = "State ID"
    case insuranceCard = "Insurance card"
    case utilityBill = "Utility bill"
    case bankStatement = "Bank statement"
    case taxDocument = "Tax document"
    case employmentDocument = "Employment document"
    case ssnCard = "Social Security card"
    case other = "Other document"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .driversLicense: return "car.fill"
        case .passport: return "globe"
        case .stateId: return "person.text.rectangle.fill"
        case .insuranceCard: return "cross.case.fill"
        case .utilityBill: return "bolt.fill"
        case .bankStatement: return "building.columns.fill"
        case .taxDocument: return "doc.text.fill"
        case .employmentDocument: return "briefcase.fill"
        case .ssnCard: return "person.text.rectangle.fill"
        case .other: return "doc.text.viewfinder"
        }
    }
}

enum ProfileSchema {
    static let allFields: [ProfileFieldDefinition] = [
        // Identity — name, then DOB / gender
        ProfileFieldDefinition(key: ProfileFieldKey.displayName, label: "Display name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.relationship, label: "Household role", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalFirstName, label: "Legal first name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalMiddleName, label: "Legal middle name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalLastName, label: "Legal last name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.dateOfBirth, label: "Date of birth", section: .identity, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.gender, label: "Gender", section: .identity, isSensitive: false),
        // Contact
        ProfileFieldDefinition(key: ProfileFieldKey.email, label: "Email", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.phoneMobile, label: "Mobile phone", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.phoneHome, label: "Home phone", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.utilityProvider, label: "Utility provider", section: .contact, isSensitive: false),
        // Address — street through country
        ProfileFieldDefinition(key: ProfileFieldKey.addressLine1, label: "Address line 1", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.addressLine2, label: "Address line 2", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.city, label: "City", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.state, label: "State / province", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.postalCode, label: "ZIP / postal code", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.country, label: "Country", section: .address, isSensitive: false),
        // Government IDs — number, issuer, issue, expiry per document
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseNumber, label: "Driver license number", section: .governmentIds, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseState, label: "Driver license state", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseIssueDate, label: "Driver license issue date", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseExpiry, label: "Driver license expiry", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.stateIdNumber, label: "State ID number", section: .governmentIds, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.stateIdExpiry, label: "State ID expiry", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportNumber, label: "Passport number", section: .governmentIds, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.passportCountry, label: "Passport country", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportIssueDate, label: "Passport issue date", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportIssuedPlace, label: "Passport issued place", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportAddress, label: "Passport address", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportExpiry, label: "Passport expiry", section: .governmentIds, isSensitive: false),
        // Tax & financial
        ProfileFieldDefinition(key: ProfileFieldKey.ssn, label: "SSN", section: .tax, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.filingStatus, label: "Filing status", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.taxFormType, label: "Tax form type", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.taxYear, label: "Tax year", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.employerName, label: "Employer", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.bankName, label: "Bank name", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.bankAccountLast4, label: "Bank account (last 4)", section: .tax, isSensitive: true),
        // Medical / insurance
        ProfileFieldDefinition(key: ProfileFieldKey.insuranceCarrier, label: "Insurance carrier", section: .medical, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.insuranceMemberId, label: "Insurance member ID", section: .medical, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.emergencyContactName, label: "Emergency contact name", section: .medical, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.emergencyContactPhone, label: "Emergency contact phone", section: .medical, isSensitive: false),
    ]

    static func definition(for key: String) -> ProfileFieldDefinition? {
        allFields.first { $0.key == key }
    }

    static func fields(in section: ProfileSection) -> [ProfileFieldDefinition] {
        allFields.filter { $0.section == section }
    }

    static func isCanonicalKey(_ key: String) -> Bool {
        allFields.contains { $0.key == key }
    }

    /// Human-readable label for extension (dynamic) fields not in the canonical schema.
    static func label(forExtensionKey key: String) -> String {
        if let def = definition(for: key) { return def.label }
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    struct FieldGroup: Identifiable {
        let title: String
        let items: [OcrFieldSuggestion]
        var id: String { title }
    }

    /// Canonical display order: identity → contact → address → IDs (number/issue/expiry blocks) → tax → medical.
    static func sortIndex(for key: String) -> Int {
        allFields.firstIndex(where: { $0.key == key }) ?? Int.max
    }

    static func sortSuggestions(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        suggestions.sorted { lhs, rhs in
            let left = sortIndex(for: lhs.profileKey)
            let right = sortIndex(for: rhs.profileKey)
            if left != right { return left < right }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    static func groupedSuggestions(_ suggestions: [OcrFieldSuggestion]) -> [FieldGroup] {
        let sorted = sortSuggestions(suggestions)
        var groups: [FieldGroup] = []
        for section in ProfileSection.allCases {
            let items = sorted.filter { definition(for: $0.profileKey)?.section == section }
            if !items.isEmpty {
                groups.append(FieldGroup(title: section.rawValue, items: items))
            }
        }
        let extensionItems = sorted.filter { !isCanonicalKey($0.profileKey) }
        if !extensionItems.isEmpty {
            groups.append(FieldGroup(title: "Additional fields", items: extensionItems))
        }
        return groups
    }
}
