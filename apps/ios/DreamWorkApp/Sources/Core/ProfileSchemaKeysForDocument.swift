import Foundation

/// Narrows LLM / mapper schema prompts to fields relevant to an inferred document category.
enum ProfileSchemaKeysForDocument {
    static func inferOpenType(from text: String) -> String {
        let upper = text.uppercased()
        if upper.contains("AADHAAR") || upper.contains("UIDAI") { return "aadhaar_card" }
        if upper.contains("PERMANENT ACCOUNT") || upper.contains(" PAN ") { return "pan_card" }
        if upper.contains("DRIVER") && upper.contains("LICENSE") { return "drivers_license" }
        if upper.contains("PASSPORT") { return "passport" }
        if upper.contains("VISA") { return "visa" }
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
        _ = openType
        _ = fallbackToAll
        return []
    }
}
