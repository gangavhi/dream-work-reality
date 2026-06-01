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

        // Document-agnostic path: only decode true machine-readable zones (MRZ / barcode).
        // Do not run keyword-triggered DL/passport OCR parsers on generic layout text.
        guard !mrzHintText.isEmpty else {
            return finalize(suggestions: suggestions, sources: sources)
        }

        if IndianPassportParser.isIndianPassport(mrzHintText) {
            let parsed = IndianPassportParser.suggestions(from: mrzHintText)
            if !parsed.isEmpty {
                suggestions = mergeTrusted(parsed, into: suggestions)
                sources.append("passport")
            }
        } else if PassportParser.isPassport(mrzHintText) {
            let parsed = PassportParser.suggestions(from: mrzHintText)
            if !parsed.isEmpty {
                suggestions = mergeTrusted(parsed, into: suggestions)
                sources.append("passport")
            }
        }

        _ = plain
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
