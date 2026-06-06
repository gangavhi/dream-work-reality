import Foundation

/// Region- and format-specific parsers wired into the main scan pipeline (not only Forms flow).
enum SpecializedDocumentExtractors {
    static func suggestions(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        openDocumentType: String?,
        classification: ClassificationAgent.Result
    ) -> [OcrFieldSuggestion] {
        let presentation = DocumentTypePresentation.resolve(
            openDocumentType ?? classification.openDocumentType
        )
        let corpus = layout.layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corpus.isEmpty else { return [] }

        var merged: [OcrFieldSuggestion] = []

        let lines = corpus
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if presentation.enumType == .driversLicense || presentation.enumType == .stateId {
            if let texas = TexasDriverLicenseParser.parse(from: lines, joined: corpus) {
                let texasFields = DriverLicenseFieldMapper.suggestions(from: texas)
                    .map { $0.withMappingSource(.onDevice) }
                merged = CoreIngestHTTPClient.mergeSuggestions(trusted: texasFields, supplemental: merged)
            }
            let genericDL = DriverLicenseParser.parse(corpus)
            let dlFields = DriverLicenseFieldMapper.suggestions(from: genericDL)
                .map { $0.withMappingSource(.onDevice) }
            merged = CoreIngestHTTPClient.mergeSuggestions(trusted: merged, supplemental: dlFields)
        }

        if presentation.enumType == .passport || IndianPassportParser.isIndianPassport(corpus) {
            let passportFields = OcrFieldSuggester.suggest(from: corpus, documentType: .passport)
                .map { $0.withMappingSource(.onDevice) }
            merged = CoreIngestHTTPClient.mergeSuggestions(trusted: merged, supplemental: passportFields)
        }

        let typeScoped = OcrFieldSuggester.suggest(from: corpus, documentType: presentation.enumType)
            .map { $0.withMappingSource(.onDevice) }
        merged = CoreIngestHTTPClient.mergeSuggestions(trusted: merged, supplemental: typeScoped)

        if presentation.enumType == .taxDocument {
            let upper = corpus.uppercased()
            if upper.contains("W-2") || upper.range(of: #"\bW2\b"#, options: .regularExpression) != nil {
                merged.append(
                    OcrFieldSuggestion(
                        profileKey: ProfileFieldKey.taxFormType,
                        label: "Tax form type",
                        value: "W-2",
                        confidence: "High",
                        confidenceScore: 0.9,
                        mappingSource: .onDevice
                    )
                )
            } else if upper.contains("1099") {
                merged.append(
                    OcrFieldSuggestion(
                        profileKey: ProfileFieldKey.taxFormType,
                        label: "Tax form type",
                        value: "1099",
                        confidence: "High",
                        confidenceScore: 0.9,
                        mappingSource: .onDevice
                    )
                )
            }
        }

        return merged
    }
}
