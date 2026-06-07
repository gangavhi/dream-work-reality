import Foundation

/// Rewrite v2 — stash whitelist + form-relevance gate (§5.5 implementation doc).
enum RewriteStashPolicy {
    static let stashWhitelist: Set<String> = [
        "passport", "stateId", "driversLicense", "ssnCard",
        "utility_bill", "utilityBill", "lease",
        "insuranceCard", "bankStatement",
        "w2", "form1099", "payStub",
        "immunizationRecord", "birthCertificate",
    ]

    static let formRelevantExtract: Set<String> = [
        "passport", "stateId", "driversLicense", "ssnCard",
        "utility_bill", "utilityBill", "lease",
        "insuranceCard", "bankStatement",
        "immunizationRecord",
        "visa", "workAuthorization", "immigrationForm",
    ]

    static func shouldStash(documentType: String) -> Bool {
        stashWhitelist.contains(documentType)
    }

    static func isFormRelevant(documentType: String) -> Bool {
        formRelevantExtract.contains(documentType)
    }

    static func canonicalType(for scanned: ScannedDocumentType, ocrText: String? = nil) -> String {
        switch scanned {
        case .driversLicense: return "driversLicense"
        case .passport: return "passport"
        case .stateId: return "stateId"
        case .insuranceCard: return "insuranceCard"
        case .utilityBill: return "utility_bill"
        case .bankStatement: return "bankStatement"
        case .taxDocument: return canonicalTaxType(from: ocrText)
        case .employmentDocument: return "payStub"
        case .ssnCard: return "ssnCard"
        case .other: return "unknown"
        }
    }

    private static func canonicalTaxType(from ocrText: String?) -> String {
        let text = ocrText?.uppercased() ?? ""
        if text.contains("1099") { return "form1099" }
        if text.contains("W-2") || text.contains("W2") { return "w2" }
        return "w2"
    }

    static func displayLabel(for canonicalType: String) -> String {
        switch canonicalType {
        case "passport": return "Passport"
        case "stateId": return "State ID"
        case "driversLicense": return "Driver License"
        case "ssnCard": return "SSN Card"
        case "utility_bill", "utilityBill": return "Utility Bill"
        case "lease": return "Lease"
        case "insuranceCard": return "Insurance Card"
        case "bankStatement": return "Bank Statement"
        case "w2": return "W-2"
        case "form1099": return "1099"
        case "payStub": return "Pay Stub"
        case "immunizationRecord": return "Immunization Record"
        case "birthCertificate": return "Birth Certificate"
        default: return canonicalType
        }
    }
}

/// Must-have household document categories (§5.4).
enum MustHaveDocumentCategory: String, CaseIterable, Identifiable {
    case passportOrID = "Passport / ID"
    case driverLicense = "Driver License"
    case ssnCard = "SSN Card"
    case addressProof = "Address Proof"
    case insuranceCard = "Insurance Card"
    case taxForms = "W-2 / 1099 / Pay stub"
    case bankStatement = "Bank Statement"
    case emergencyContact = "Emergency Contact"
    case employment = "Employment Information"

    var id: String { rawValue }

    var stashTypes: [String] {
        switch self {
        case .passportOrID: return ["passport", "stateId"]
        case .driverLicense: return ["driversLicense"]
        case .ssnCard: return ["ssnCard"]
        case .addressProof: return ["utility_bill", "lease"]
        case .insuranceCard: return ["insuranceCard"]
        case .taxForms: return ["w2", "form1099", "payStub"]
        case .bankStatement: return ["bankStatement"]
        case .emergencyContact, .employment: return []
        }
    }

    var isManualOnly: Bool {
        self == .emergencyContact || self == .employment
    }

    func isComplete(person: PersonRecord, stashedTypes: Set<String>) -> Bool {
        if isManualOnly {
            switch self {
            case .emergencyContact:
                return !person.value(for: ProfileFieldKey.emergencyContactName).isEmpty
                    || !person.value(for: ProfileFieldKey.emergencyContactPhone).isEmpty
            case .employment:
                return !person.value(for: ProfileFieldKey.employerName).isEmpty
            default: return false
            }
        }
        let hasStash = stashTypes.contains(where: { self.stashTypes.contains($0) })
        return hasStash || hasExtractedFields(person: person, stashedTypes: stashedTypes)
    }

    private func hasExtractedFields(person: PersonRecord, stashedTypes: Set<String>) -> Bool {
        switch self {
        case .passportOrID:
            return !person.value(for: ProfileFieldKey.passportNumber).isEmpty
                || !person.value(for: ProfileFieldKey.stateIdNumber).isEmpty
        case .driverLicense:
            return !person.value(for: ProfileFieldKey.driversLicenseNumber).isEmpty
        case .ssnCard:
            return !person.value(for: ProfileFieldKey.ssn).isEmpty
        case .addressProof:
            return !person.value(for: ProfileFieldKey.addressLine1).isEmpty
                || !person.value(for: ProfileFieldKey.city).isEmpty
        case .insuranceCard:
            return !person.value(for: ProfileFieldKey.insuranceMemberId).isEmpty
        case .taxForms:
            return stashedTypes.contains(where: { ["w2", "form1099", "payStub"].contains($0) })
        case .bankStatement:
            return !person.value(for: ProfileFieldKey.bankName).isEmpty
        default:
            return false
        }
    }
}
