import Foundation

/// Maps open-vocabulary model `document_type` strings to UI enum + human label (cosmetic only).
enum DocumentTypePresentation {
    static func resolve(_ openType: String?) -> (enumType: ScannedDocumentType, displayLabel: String) {
        let raw = openType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return (.other, "Document")
        }

        let normalized = raw.lowercased().replacingOccurrences(of: "-", with: "_")
        let enumType: ScannedDocumentType = {
            switch normalized {
            case "drivers_license", "driver_license", "drivers license", "driving_licence", "driverslicense":
                return .driversLicense
            case "passport":
                return .passport
            case "visa":
                return .other
            case "state_id", "state_identification", "identification_card", "stateid":
                return .stateId
            case "insurance_card", "health_insurance_card", "insurancecard":
                return .insuranceCard
            case "utility_bill", "utilitybill":
                return .utilityBill
            case "bank_statement", "bankstatement":
                return .bankStatement
            case "tax_form", "tax_document", "taxdocument", "w2", "w_2", "1099", "form_1040", "form1099":
                return .taxDocument
            case "employment_document", "pay_stub", "paystub", "employmentdocument":
                return .employmentDocument
            case "ssn_card", "social_security_card", "social_security", "ssncard":
                return .ssnCard
            case "aadhaar_card", "aadhaar":
                return .other
            case "pan_card", "pan":
                return .other
            case "tax_w2", "tax_1099":
                return .taxDocument
            case "medical_record":
                return .other
            case "vehicle_registration":
                return .other
            default:
                return .other
            }
        }()

        let label = humanizedLabel(raw, enumType: enumType)
        return (enumType, label)
    }

    private static func humanizedLabel(_ raw: String, enumType: ScannedDocumentType) -> String {
        if enumType != .other {
            return enumType.rawValue
        }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.count <= 3 ? String(word).uppercased() : String(word).capitalized
            }
            .joined(separator: " ")
    }
}
