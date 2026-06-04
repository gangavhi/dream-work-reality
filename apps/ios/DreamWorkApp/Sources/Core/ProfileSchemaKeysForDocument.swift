import Foundation

/// Narrows LLM / mapper schema prompts to fields relevant to an inferred document category.
enum ProfileSchemaKeysForDocument {
    static func inferOpenType(from text: String) -> String {
        let upper = text.uppercased()
        if upper.contains("AADHAAR") || upper.contains("UIDAI") { return "aadhaar_card" }
        if upper.contains("PERMANENT ACCOUNT") || upper.contains(" PAN ") { return "pan_card" }
        if upper.contains("DRIVER") && upper.contains("LICENSE") { return "drivers_license" }
        if upper.contains("PASSPORT") || upper.contains("P<") { return "passport" }
        if upper.contains("VISA") { return "visa" }
        if upper.contains("INSURANCE") || upper.contains("MEMBER ID") || upper.contains("GROUP #") {
            return "insurance_card"
        }
        if upper.contains("STATE ID") || upper.contains("IDENTIFICATION CARD") { return "state_id" }
        if upper.contains("SOCIAL SECURITY") { return "social_security_card" }
        if upper.contains("W-2") || upper.contains("W2 ") { return "tax_w2" }
        if upper.contains("1099") { return "tax_1099" }
        if upper.contains("BANK STATEMENT") { return "bank_statement" }
        if upper.contains("UTILITY") || upper.contains("ELECTRIC") || upper.contains("WATER BILL") {
            return "utility_bill"
        }
        if upper.contains("PAY STUB") { return "employment_document" }
        if upper.contains("MEDICAL") || upper.contains("PATIENT") || upper.contains("DIAGNOSIS") {
            return "medical_record"
        }
        return "other"
    }

    static func keys(forOpenDocumentType openType: String?, fallbackToAll: Bool = true) -> [String] {
        guard let openType else {
            return fallbackToAll ? ProfileSchema.allFields.map(\.key) : commonIdentityKeys
        }
        let normalized = openType
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "drivers_license", "driver_license", "driving_licence":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalMiddleName,
                ProfileFieldKey.legalLastName,
                ProfileFieldKey.dateOfBirth, ProfileFieldKey.driversLicenseNumber, ProfileFieldKey.driversLicenseState,
                ProfileFieldKey.driversLicenseIssueDate, ProfileFieldKey.driversLicenseExpiry,
                ProfileFieldKey.addressLine1, ProfileFieldKey.addressLine2, ProfileFieldKey.city,
                ProfileFieldKey.state, ProfileFieldKey.postalCode, ProfileFieldKey.gender,
            ]
        case "passport":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
                ProfileFieldKey.dateOfBirth, ProfileFieldKey.passportNumber, ProfileFieldKey.passportCountry,
                ProfileFieldKey.passportExpiry, ProfileFieldKey.gender, ProfileFieldKey.country,
                ProfileFieldKey.addressLine1, ProfileFieldKey.city, ProfileFieldKey.state, ProfileFieldKey.postalCode,
            ]
        case "insurance_card":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
                ProfileFieldKey.insuranceMemberId, ProfileFieldKey.insuranceCarrier,
                ProfileFieldKey.dateOfBirth, ProfileFieldKey.addressLine1,
            ]
        case "state_id", "identification_card":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
                ProfileFieldKey.dateOfBirth, ProfileFieldKey.stateIdNumber, ProfileFieldKey.stateIdExpiry,
                ProfileFieldKey.addressLine1, ProfileFieldKey.city, ProfileFieldKey.state, ProfileFieldKey.postalCode,
            ]
        case "utility_bill":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.addressLine1, ProfileFieldKey.city,
                ProfileFieldKey.state, ProfileFieldKey.postalCode, ProfileFieldKey.utilityProvider,
            ]
        case "medical_record":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.dateOfBirth, ProfileFieldKey.insuranceMemberId,
                ProfileFieldKey.emergencyContactName, ProfileFieldKey.emergencyContactPhone,
            ]
        case "bank_statement":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.bankName, ProfileFieldKey.bankAccountLast4,
                ProfileFieldKey.addressLine1,
            ]
        case "social_security_card", "ssn_card":
            return [ProfileFieldKey.displayName, ProfileFieldKey.ssn, ProfileFieldKey.dateOfBirth]
        case "tax_w2", "tax_1099", "tax_form":
            return [
                ProfileFieldKey.displayName, ProfileFieldKey.employerName, ProfileFieldKey.taxYear,
                ProfileFieldKey.ssn, ProfileFieldKey.filingStatus,
            ]
        case "employment_document", "pay_stub":
            return [ProfileFieldKey.displayName, ProfileFieldKey.employerName, ProfileFieldKey.addressLine1]
        default:
            return fallbackToAll ? ProfileSchema.allFields.map(\.key) : []
        }
    }

    private static let commonIdentityKeys: [String] = [
        ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
        ProfileFieldKey.dateOfBirth, ProfileFieldKey.addressLine1, ProfileFieldKey.city,
        ProfileFieldKey.state, ProfileFieldKey.postalCode, ProfileFieldKey.phoneMobile, ProfileFieldKey.email,
    ]
}
