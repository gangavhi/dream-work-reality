import Foundation

/// Assembles scan review output and document understanding from Apple-native extraction.
enum AppleProfileBuilder {
    static func buildUnderstanding(
        classification: NLDocumentClassifier.Result,
        suggestions: [OcrFieldSuggestion]
    ) -> DocumentUnderstandingResult {
        let issuer = suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseState })?.value
            ?? suggestions.first(where: { $0.profileKey == ProfileFieldKey.passportCountry })?.value
        let displayHint = suggestions.first(where: { $0.profileKey == ProfileFieldKey.displayName })?.value
        return DocumentUnderstandingResult(
            documentType: classification.openLabel,
            documentTypeConfidence: classification.confidence,
            issuerRegion: issuer,
            displayNameHint: displayHint,
            usedAI: false
        )
    }

    static func finalize(
        suggestions: [OcrFieldSuggestion],
        plainText: String,
        documentType: ScannedDocumentType
    ) -> [OcrFieldSuggestion] {
        var sorted = ProfileSchema.sortSuggestions(suggestions)
        sorted = PersonNameResolver.apply(to: sorted, ocrText: plainText, documentType: documentType)
        return sorted
    }
}
