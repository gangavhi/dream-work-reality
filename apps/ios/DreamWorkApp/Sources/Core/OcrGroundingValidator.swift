import Foundation

/// Drops mapped values that do not appear in OCR text (reduces hallucinated/heuristic false positives).
enum OcrGroundingValidator {
    /// Keys that may be filled from barcode/MRZ decode without appearing verbatim in OCR.
    private static let machineReadableKeys: Set<String> = [
        ProfileFieldKey.driversLicenseNumber,
        ProfileFieldKey.driversLicenseState,
        ProfileFieldKey.driversLicenseExpiry,
        ProfileFieldKey.driversLicenseIssueDate,
        ProfileFieldKey.passportNumber,
        ProfileFieldKey.passportExpiry,
        ProfileFieldKey.passportCountry,
        ProfileFieldKey.legalFirstName,
        ProfileFieldKey.legalLastName,
        ProfileFieldKey.legalMiddleName,
        ProfileFieldKey.displayName,
        ProfileFieldKey.dateOfBirth,
        ProfileFieldKey.gender,
        ProfileFieldKey.country,
    ]

    static func filter(
        _ suggestions: [OcrFieldSuggestion],
        ocrCorpus: String,
        trustedProfileKeys: Set<String> = []
    ) -> [OcrFieldSuggestion] {
        let corpus = normalize(corpus: ocrCorpus)
        guard !corpus.isEmpty else { return suggestions }

        return suggestions.filter { suggestion in
            if suggestion.mappingSource == .barcode || suggestion.mappingSource == .mrz {
                return true
            }
            if trustedProfileKeys.contains(suggestion.profileKey) {
                return true
            }
            if machineReadableKeys.contains(suggestion.profileKey),
               suggestion.confidenceScore >= 0.85
            {
                return true
            }
            return isGrounded(value: suggestion.value, in: corpus)
        }
    }

    static func isGrounded(value: String, in corpus: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normValue = normalize(token: trimmed)
        if !normValue.isEmpty {
            if corpus.contains(normValue) {
                return true
            }
            let compactCorpus = corpus.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            if compactCorpus.contains(normValue) {
                return true
            }
        }

        let digitsOnly = trimmed.filter(\.isNumber)
        if digitsOnly.count >= 4 {
            let corpusDigits = corpus.filter(\.isNumber)
            if corpusDigits.contains(digitsOnly) {
                return true
            }
        }

        // Last-name / token match for multi-word values.
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { normalize(token: String($0)) }
            .filter { $0.count >= 3 }
        if parts.count >= 2, parts.allSatisfy({ corpus.contains($0) }) {
            return true
        }

        return false
    }

    private static func normalize(corpus: String) -> String {
        corpus.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9@.\-/ ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
