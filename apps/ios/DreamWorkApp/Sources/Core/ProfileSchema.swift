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
    static let passportExpiry = "passport_expiry"
    static let insuranceCarrier = "insurance_carrier"
    static let insuranceMemberId = "insurance_member_id"
    static let emergencyContactName = "emergency_contact_name"
    static let emergencyContactPhone = "emergency_contact_phone"
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
    case insuranceCard = "Insurance card"
    case other = "Other document"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .driversLicense: return "car.fill"
        case .passport: return "globe"
        case .insuranceCard: return "cross.case.fill"
        case .other: return "doc.text.viewfinder"
        }
    }
}

enum ProfileSchema {
    static let allFields: [ProfileFieldDefinition] = [
        ProfileFieldDefinition(key: ProfileFieldKey.displayName, label: "Display name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.relationship, label: "Household role", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalFirstName, label: "Legal first name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalMiddleName, label: "Legal middle name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.legalLastName, label: "Legal last name", section: .identity, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.dateOfBirth, label: "Date of birth", section: .identity, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.email, label: "Email", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.phoneMobile, label: "Mobile phone", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.phoneHome, label: "Home phone", section: .contact, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.addressLine1, label: "Address line 1", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.addressLine2, label: "Address line 2", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.city, label: "City", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.state, label: "State / province", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.postalCode, label: "ZIP / postal code", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.country, label: "Country", section: .address, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.ssn, label: "SSN", section: .tax, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.filingStatus, label: "Filing status", section: .tax, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseNumber, label: "Driver license number", section: .governmentIds, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseState, label: "Driver license state", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseIssueDate, label: "Driver license issue date", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.driversLicenseExpiry, label: "Driver license expiry", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportNumber, label: "Passport number", section: .governmentIds, isSensitive: true),
        ProfileFieldDefinition(key: ProfileFieldKey.passportCountry, label: "Passport country", section: .governmentIds, isSensitive: false),
        ProfileFieldDefinition(key: ProfileFieldKey.passportExpiry, label: "Passport expiry", section: .governmentIds, isSensitive: false),
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
}
