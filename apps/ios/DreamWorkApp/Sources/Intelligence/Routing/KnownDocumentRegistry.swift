import Foundation

/// Document types with specialized fast parsers, layout priors, or machine-readable decoders.
enum KnownDocumentRegistry {
    static let knownOpenTypes: Set<String> = [
        "drivers_license", "driver_license", "driving_licence",
        "passport",
        "insurance_card",
        "state_id", "identification_card",
        "utility_bill",
        "medical_record",
        "bank_statement",
        "social_security_card", "ssn_card",
        "tax_w2", "tax_1099", "tax_form",
        "employment_document", "pay_stub",
    ]

    static func isKnown(openType: String?) -> Bool {
        guard let openType else { return false }
        let normalized = openType
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return knownOpenTypes.contains(normalized)
    }

    static func hasMachineReadableSignal(_ hints: EmbeddedPayloadHints.Result) -> Bool {
        !hints.mrzLines.isEmpty || !hints.barcodePayloads.isEmpty
    }

    static func hasStructuredLayout(_ layout: LayoutIntelligenceAgent.LayoutDocument) -> Bool {
        layout.labelValuePairs.count >= 2
    }
}
