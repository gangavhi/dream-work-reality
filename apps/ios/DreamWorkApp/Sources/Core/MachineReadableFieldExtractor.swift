import Foundation

/// Decodes PDF417 (AAMVA) and MRZ payloads into profile fields without network LLM (Phase A).
enum MachineReadableFieldExtractor {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var decodedPayload: Bool
        var sources: [String]
    }

    static func extract(
        from hints: EmbeddedPayloadHints.Result,
        supplementalOCRText: String
    ) -> Result {
        var suggestions: [OcrFieldSuggestion] = []
        var sources: [String] = []

        for payload in hints.barcodePayloads {
            guard let scan = DriverLicenseParser.parseAAMVAPDF417(payload) else { continue }
            suggestions = mergeTrusted(
                DriverLicenseFieldMapper.suggestions(from: scan),
                into: suggestions
            )
            sources.append("pdf417")
        }

        if !hints.mrzLines.isEmpty {
            let mrzText = hints.mrzLines.joined(separator: "\n")
            let combined = mrzText + "\n" + supplementalOCRText
            if IndianPassportParser.isIndianPassport(combined) {
                let indian = IndianPassportParser.suggestions(from: combined)
                if !indian.isEmpty {
                    suggestions = mergeTrusted(indian, into: suggestions)
                    sources.append("mrz")
                }
            } else if PassportParser.isPassport(combined) || PassportParser.isPassport(mrzText) {
                let passport = PassportParser.suggestions(from: combined)
                if !passport.isEmpty {
                    suggestions = mergeTrusted(passport, into: suggestions)
                    sources.append("mrz")
                }
            }
        }

        let tagged = suggestions.map { suggestion -> OcrFieldSuggestion in
            let source: FieldMappingSource = sources.contains("mrz") ? .mrz : .barcode
            return suggestion.withMappingSource(source)
        }

        return Result(
            suggestions: ProfileSchema.sortSuggestions(tagged),
            decodedPayload: !sources.isEmpty,
            sources: sources
        )
    }

    /// Machine-readable fields win; supplemental only fills missing keys or lower confidence.
    static func mergeTrusted(
        _ trusted: [OcrFieldSuggestion],
        into existing: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: trusted, supplemental: existing)
    }
}
