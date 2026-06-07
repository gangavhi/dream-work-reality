import Foundation

/// Type-specific field extraction — no UniversalDocumentParser, no remote AI.
enum RewriteFieldExtractor {
    static func extract(
        from fullText: String,
        documentType: ScannedDocumentType,
        machineReadable: MachineReadableFieldExtractor.Result
    ) -> [OcrFieldSuggestion] {
        let layout = layoutExtract(from: fullText, documentType: documentType)
        if machineReadable.suggestions.isEmpty {
            return layout
        }
        return MachineReadableFieldExtractor.mergeTrusted(machineReadable.suggestions, into: layout)
    }

    private static func layoutExtract(
        from text: String,
        documentType: ScannedDocumentType
    ) -> [OcrFieldSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let canonical = RewriteStashPolicy.canonicalType(for: documentType, ocrText: text)
        guard RewriteStashPolicy.isFormRelevant(documentType: canonical) else {
            return []
        }

        switch documentType {
        case .driversLicense:
            return DriverLicenseFieldMapper.suggestions(from: DriverLicenseParser.parse(trimmed))
        case .stateId:
            let dl = DriverLicenseFieldMapper.suggestions(from: DriverLicenseParser.parse(trimmed))
            return remapToStateId(dl)
        case .passport:
            if IndianPassportParser.isIndianPassport(trimmed) {
                let indian = IndianPassportParser.suggestions(from: trimmed)
                if !indian.isEmpty { return indian }
            }
            let passport = PassportParser.suggestions(from: trimmed)
            if !passport.isEmpty { return passport }
            return IndianPassportParser.suggestions(from: trimmed)
        case .ssnCard:
            return UniversalDocumentParser.parse(from: trimmed)
        case .insuranceCard:
            let parsed = InsuranceCardParser.suggestions(from: trimmed)
            if !parsed.isEmpty { return parsed }
            return OcrFieldSuggester.suggestInsuranceCardPublic(from: trimmed)
        case .utilityBill:
            return OcrFieldSuggester.suggestUtilityBillPublic(from: trimmed)
        case .bankStatement:
            return OcrFieldSuggester.suggestBankStatementPublic(from: trimmed)
        default:
            if UniversalDocumentParser.looksLikeSSNDocument(trimmed) {
                return UniversalDocumentParser.parse(from: trimmed)
            }
            return []
        }
    }

    private static func remapToStateId(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        guard let idNumber = suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseNumber }) else {
            return suggestions
        }
        let context = DocumentFieldLabelContext(documentType: .stateId, issuerRegion: nil, country: "US")
        var out = suggestions.filter {
            $0.profileKey != ProfileFieldKey.driversLicenseNumber
                && $0.profileKey != ProfileFieldKey.driversLicenseState
        }
        out.append(
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.stateIdNumber,
                label: DocumentFieldLabels.label(for: ProfileFieldKey.stateIdNumber, context: context),
                value: idNumber.value,
                confidence: idNumber.confidence,
                confidenceScore: max(idNumber.confidenceScore, 0.82),
                mappingSource: .onDevice
            )
        )
        return out
    }
}
