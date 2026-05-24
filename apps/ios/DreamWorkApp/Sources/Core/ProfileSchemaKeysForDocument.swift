import Foundation

/// Narrows LLM / mapper schema prompts to fields relevant to an inferred document category.
enum ProfileSchemaKeysForDocument {
    private static let identity: [String] = [
        ProfileFieldKey.displayName,
        ProfileFieldKey.legalFirstName,
        ProfileFieldKey.legalMiddleName,
        ProfileFieldKey.legalLastName,
        ProfileFieldKey.dateOfBirth,
        ProfileFieldKey.gender,
        ProfileFieldKey.ssn,
        ProfileFieldKey.email,
        ProfileFieldKey.phoneMobile,
        ProfileFieldKey.phoneHome,
    ]

    private static let address: [String] = [
        ProfileFieldKey.addressLine1,
        ProfileFieldKey.addressLine2,
        ProfileFieldKey.city,
        ProfileFieldKey.state,
        ProfileFieldKey.postalCode,
        ProfileFieldKey.country,
    ]

    static func inferOpenType(from text: String) -> String {
        let upper = text.uppercased()
        if upper.contains("AADHAAR") || upper.contains("UIDAI") { return "aadhaar_card" }
        if upper.contains("PERMANENT ACCOUNT") || upper.contains(" PAN ") { return "pan_card" }
        if upper.contains("DRIVER") && upper.contains("LICENSE") { return "drivers_license" }
        if upper.contains("PASSPORT") { return "passport" }
        if upper.contains("INSURANCE") || upper.contains("MEMBER ID") { return "insurance_card" }
        if upper.contains("SOCIAL SECURITY") { return "social_security_card" }
        if upper.contains("W-2") || upper.contains("W2 ") { return "tax_w2" }
        if upper.contains("1099") { return "tax_1099" }
        if upper.contains("BANK STATEMENT") { return "bank_statement" }
        if upper.contains("UTILITY") || upper.contains("ELECTRIC") { return "utility_bill" }
        if upper.contains("PAY STUB") { return "employment_document" }
        if upper.contains("MEDICAL") && upper.contains("PATIENT") { return "medical_record" }
        return "other"
    }

    static func keys(forOpenDocumentType openType: String?, fallbackToAll: Bool = true) -> [String] {
        let normalized = (openType ?? "other").lowercased().replacingOccurrences(of: "-", with: "_")
        let base: [String]
        switch normalized {
        case "drivers_license", "driver_license", "state_id", "state_identification":
            base = identity + address + [
                ProfileFieldKey.driversLicenseNumber,
                ProfileFieldKey.driversLicenseState,
                ProfileFieldKey.driversLicenseExpiry,
                ProfileFieldKey.driversLicenseIssueDate,
            ]
        case "passport":
            base = identity + [
                ProfileFieldKey.passportNumber,
                ProfileFieldKey.passportExpiry,
                ProfileFieldKey.passportCountry,
                ProfileFieldKey.country,
                "place_of_birth",
                "place_of_issue",
            ] + address
        case "aadhaar_card":
            base = identity + address + ["aadhaar_number"]
        case "pan_card":
            base = identity + ["pan_number", ProfileFieldKey.dateOfBirth]
        case "social_security_card", "ssn_card":
            base = identity + [ProfileFieldKey.ssn, ProfileFieldKey.dateOfBirth]
        case "insurance_card":
            base = identity + address + [
                ProfileFieldKey.insuranceMemberId,
                ProfileFieldKey.insuranceCarrier,
            ]
        case "utility_bill":
            base = identity + address + [
                ProfileFieldKey.utilityProvider,
            ]
        case "bank_statement":
            base = identity + address + [
                ProfileFieldKey.bankName,
                ProfileFieldKey.bankAccountLast4,
            ]
        case "tax_w2", "tax_1099", "tax_form", "tax_document":
            base = identity + address + [
                ProfileFieldKey.employerName,
                ProfileFieldKey.taxFormType,
                ProfileFieldKey.taxYear,
                ProfileFieldKey.ssn,
                ProfileFieldKey.filingStatus,
            ]
        case "employment_document", "pay_stub":
            base = identity + address + [
                ProfileFieldKey.employerName,
            ]
        case "medical_record":
            base = identity + address + [
                ProfileFieldKey.insuranceMemberId,
                ProfileFieldKey.emergencyContactName,
                ProfileFieldKey.emergencyContactPhone,
            ]
        default:
            if fallbackToAll {
                return ProfileSchema.allFields.map(\.key)
            }
            base = identity + address
        }
        var seen = Set<String>()
        return base.filter { seen.insert($0).inserted }
    }
}
