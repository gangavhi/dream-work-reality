import Foundation

/// Decodes machine-readable payloads (PDF417, MRZ, passport biodata, driver license OCR) from any document.
enum MachineReadableFieldExtractor {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var decodedPayload: Bool
        /// Decode channel tags: `pdf417`, `passport`, `drivers_license`
        var sources: [String]
    }

    static func extract(
        from hints: EmbeddedPayloadHints.Result,
        plainOCRText: String
    ) -> Result {
        var suggestions: [OcrFieldSuggestion] = []
        var sources: [String] = []

        for payload in hints.barcodePayloads {
            guard let scan = DriverLicenseParser.parseAAMVAPDF417(payload) else { continue }
            suggestions = mergeTrusted(
                DriverLicenseFieldMapper.suggestions(from: scan).map { $0.withMappingSource(.barcode) },
                into: suggestions
            )
            sources.append("pdf417")
        }

        let plain = plainOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mrzHintText = hints.mrzLines.joined(separator: "\n")
        let combined = [mrzHintText, plain].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !combined.isEmpty else {
            return finalize(suggestions: suggestions, sources: sources)
        }

        if DriverLicenseParser.isDriversLicense(combined) {
            let parsed = DriverLicenseParser.suggestions(from: combined)
            if !parsed.isEmpty {
                suggestions = mergeTrusted(parsed, into: suggestions)
                sources.append("drivers_license")
            }
        }

        if IndianPassportParser.isIndianPassport(combined) {
            let parsed = IndianPassportParser.suggestions(from: combined)
            if !parsed.isEmpty {
                suggestions = mergeTrusted(parsed, into: suggestions)
                sources.append("passport")
            }
        } else if PassportParser.isPassport(combined) {
            let parsed = PassportParser.suggestions(from: combined)
            if !parsed.isEmpty {
                suggestions = mergeTrusted(parsed, into: suggestions)
                sources.append("passport")
            }
        }

        return finalize(suggestions: suggestions, sources: sources)
    }

    private static func finalize(suggestions: [OcrFieldSuggestion], sources: [String]) -> Result {
        let tagged = suggestions.map { suggestion -> OcrFieldSuggestion in
            if suggestion.mappingSource != nil {
                return suggestion
            }
            let source: FieldMappingSource = {
                if sources.contains("pdf417"),
                   suggestion.profileKey.hasPrefix("drivers_")
                    || suggestion.profileKey == ProfileFieldKey.driversLicenseNumber
                {
                    return .barcode
                }
                if sources.contains("passport") {
                    return .mrz
                }
                if sources.contains("drivers_license") {
                    return .onDevice
                }
                return .onDevice
            }()
            return suggestion.withMappingSource(source)
        }

        return Result(
            suggestions: ProfileSchema.sortSuggestions(tagged),
            decodedPayload: !sources.isEmpty,
            sources: sources
        )
    }

    static func mergeTrusted(
        _ trusted: [OcrFieldSuggestion],
        into existing: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: trusted, supplemental: existing)
    }
}
