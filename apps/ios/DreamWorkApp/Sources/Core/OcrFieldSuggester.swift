import Foundation

enum OcrFieldSuggester {
    static func suggest(from fullText: String, documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let typeSpecific = suggestForDocumentType(from: text, documentType: documentType)
        let universal = UniversalDocumentParser.parse(from: text)
        let merged = mergeSuggestions(typeSpecific, universal)
        return PersonNameResolver.apply(to: merged, ocrText: text, documentType: documentType)
    }

    private static func suggestForDocumentType(from text: String, documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        switch documentType {
        case .driversLicense:
            return suggestDriversLicense(from: text)
        case .stateId:
            return remapDriverLicenseNumberToStateId(suggestDriversLicense(from: text))
        case .ssnCard:
            return UniversalDocumentParser.parse(from: text)
        case .utilityBill:
            return suggestUtilityBill(from: text)
        case .bankStatement:
            return suggestBankStatement(from: text)
        case .taxDocument:
            return suggestTaxDocument(from: text)
        case .employmentDocument:
            return suggestEmploymentDocument(from: text)
        case .passport:
            return suggestPassport(from: text)
        case .insuranceCard:
            return suggestInsuranceCard(from: text)
        default:
            if UniversalDocumentParser.looksLikeSSNDocument(text) {
                return UniversalDocumentParser.parse(from: text)
            }
            return suggestGeneric(from: text, documentType: documentType)
        }
    }

    private static func remapDriverLicenseNumberToStateId(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
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
                confidenceScore: max(idNumber.confidenceScore, 0.82)
            )
        )
        return out
    }

    /// Uses the dedicated DL parser (labels, LAST/FIRST, address, dates) — not naive line guessing.
    private static func suggestDriversLicense(from text: String) -> [OcrFieldSuggestion] {
        let parsed = DriverLicenseParser.parse(text)
        return DriverLicenseFieldMapper.suggestions(from: parsed)
    }

    /// Dedicated passport parser — Indian biodata/MRZ first, then generic ICAO parser.
    private static func suggestPassport(from text: String) -> [OcrFieldSuggestion] {
        if IndianPassportParser.isIndianPassport(text) {
            let indian = IndianPassportParser.suggestions(from: text)
            if !indian.isEmpty { return indian }
        }

        let passport = PassportParser.suggestions(from: text)
        if !passport.isEmpty { return passport }

        let indian = IndianPassportParser.suggestions(from: text)
        if !indian.isEmpty { return indian }

        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ label: String, _ value: String, _ score: Double) {
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label,
                    value: value,
                    confidence: score >= 0.85 ? "High" : "Medium",
                    confidenceScore: score
                )
            )
        }

        let context = DocumentFieldLabelContext(documentType: .passport, issuerRegion: nil, country: "US")
        if let passport = firstMatch(in: text, pattern: #"\b([A-Z]{1,2}\d{6,9})\b"#) {
            add(
                ProfileFieldKey.passportNumber,
                DocumentFieldLabels.label(for: ProfileFieldKey.passportNumber, context: context),
                passport,
                0.72
            )
        }
        out.append(contentsOf: UniversalDocumentParser.parse(from: text).filter {
            [ProfileFieldKey.displayName, ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
             ProfileFieldKey.dateOfBirth].contains($0.profileKey)
        })
        return mergeSuggestions(out)
    }

    private static func mergeSuggestions(_ batches: [OcrFieldSuggestion]...) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for item in batches.flatMap({ $0 }) {
            if let existing = byKey[item.profileKey] {
                if item.confidenceScore > existing.confidenceScore {
                    byKey[item.profileKey] = item
                }
            } else {
                byKey[item.profileKey] = item
            }
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    private static func suggestGeneric(from text: String, documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ label: String, _ value: String, _ confidence: String, _ score: Double? = nil) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label,
                    value: trimmed,
                    confidence: confidence,
                    confidenceScore: score
                )
            )
        }

        if let email = firstMatch(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) {
            add(ProfileFieldKey.email, "Email", email, "High")
        }

        if let phone = firstMatch(in: text, pattern: #"\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}"#) {
            add(ProfileFieldKey.phoneMobile, "Mobile phone", phone, "Medium")
        }

        for pattern in [
            #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#,
            #"\b(\d{4}-\d{2}-\d{2})\b"#,
        ] {
            if let dob = firstMatch(in: text, pattern: pattern) {
                add(ProfileFieldKey.dateOfBirth, "Date of birth", dob, "Medium")
                break
            }
        }

        if let zip = firstMatch(in: text, pattern: #"\b(\d{5}(?:-\d{4})?)\b"#) {
            add(ProfileFieldKey.postalCode, "ZIP / postal code", zip, "Medium")
        }

        switch documentType {
        case .passport:
            return suggestPassport(from: text)
        case .stateId:
            if let id = firstMatch(in: text, pattern: #"(?:ID|IDENTIFICATION)[#:\s]*([A-Z0-9]{5,15})"#, options: [.caseInsensitive]) {
                let context = DocumentFieldLabelContext(documentType: .stateId, issuerRegion: nil, country: "US")
                add(
                    ProfileFieldKey.stateIdNumber,
                    DocumentFieldLabels.label(for: ProfileFieldKey.stateIdNumber, context: context),
                    id,
                    "Medium",
                    0.7
                )
            }
        case .insuranceCard:
            if let member = firstMatch(
                in: text,
                pattern: #"(?:MEMBER|ID|SUBSCRIBER)[#:\s]*([A-Z0-9]{6,20})"#,
                options: [.caseInsensitive]
            ), member.rangeOfCharacter(from: .decimalDigits) != nil {
                add(ProfileFieldKey.insuranceMemberId, "Insurance member ID", member, "Medium", 0.72)
            }
            if let carrier = firstMatch(in: text, pattern: #"^([A-Z][A-Z\s&]{3,30})$"#, options: [.caseInsensitive]) {
                add(ProfileFieldKey.insuranceCarrier, "Insurance carrier", carrier, "Low", 0.55)
            }
        default:
            break
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.profileKey).inserted }
    }

    private static func suggestInsuranceCard(from text: String) -> [OcrFieldSuggestion] {
        var out = suggestGeneric(from: text, documentType: .insuranceCard)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let carrierLine = lines.first(where: { line in
            let upper = line.uppercased()
            return upper.contains("CROSS") || upper.contains("SHIELD") || upper.contains("INSURANCE")
                || upper.contains("AETNA") || upper.contains("ANTHEM") || upper.contains("HUMANA")
        }) {
            out.append(
                OcrFieldSuggestion(
                    profileKey: ProfileFieldKey.insuranceCarrier,
                    label: "Insurance carrier",
                    value: carrierLine,
                    confidence: "Medium",
                    confidenceScore: 0.72
                )
            )
        }
        return mergeSuggestions(out)
    }

    private static func suggestUtilityBill(from text: String) -> [OcrFieldSuggestion] {
        var out = suggestGeneric(from: text, documentType: .utilityBill)
        if let provider = firstMatch(in: text, pattern: #"^([A-Z][A-Z\s&]{3,40}(?:ELECTRIC|GAS|WATER|ENERGY)?)"#, options: [.caseInsensitive]) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.utilityProvider, label: "Utility provider", value: provider, confidence: "Medium", confidenceScore: 0.68))
        }
        return out
    }

    private static func suggestBankStatement(from text: String) -> [OcrFieldSuggestion] {
        var out = suggestGeneric(from: text, documentType: .bankStatement)
        if let bank = firstMatch(in: text, pattern: #"^([A-Z][A-Z\s&]{3,30}(?:BANK|CREDIT UNION)?)"#, options: [.caseInsensitive]) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.bankName, label: "Bank name", value: bank, confidence: "Medium", confidenceScore: 0.65))
        }
        if let last4 = firstMatch(in: text, pattern: #"(?:ACCOUNT|ACCT)[#:\s]*\*{0,4}(\d{4})"#, options: [.caseInsensitive]) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.bankAccountLast4, label: "Bank account (last 4)", value: last4, confidence: "Medium", confidenceScore: 0.7))
        }
        return out
    }

    private static func suggestTaxDocument(from text: String) -> [OcrFieldSuggestion] {
        var out = suggestGeneric(from: text, documentType: .taxDocument)
        if text.uppercased().contains("W-2") || text.uppercased().contains("W2") {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.taxFormType, label: "Tax form type", value: "W-2", confidence: "High", confidenceScore: 0.88))
        } else if text.uppercased().contains("1099") {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.taxFormType, label: "Tax form type", value: "1099", confidence: "High", confidenceScore: 0.88))
        }
        if let year = firstMatch(in: text, pattern: #"\b(20\d{2})\b"#) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.taxYear, label: "Tax year", value: year, confidence: "Medium", confidenceScore: 0.75))
        }
        if let employer = firstMatch(in: text, pattern: #"(?:EMPLOYER|EMPLOYER'S NAME)[:\s]+(.{3,40})"#, options: [.caseInsensitive]) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.employerName, label: "Employer", value: employer, confidence: "Medium", confidenceScore: 0.7))
        }
        return out
    }

    private static func suggestEmploymentDocument(from text: String) -> [OcrFieldSuggestion] {
        var out = suggestGeneric(from: text, documentType: .employmentDocument)
        if let employer = firstMatch(in: text, pattern: #"(?:EMPLOYER|COMPANY)[:\s]+(.{3,40})"#, options: [.caseInsensitive]) {
            out.append(OcrFieldSuggestion(profileKey: ProfileFieldKey.employerName, label: "Employer", value: employer, confidence: "Medium", confidenceScore: 0.72))
        }
        return out
    }

    static func fullText(from document: VisionOcrAdapter.NormalizedDocument) -> String {
        document.pages
            .flatMap(\.blocks)
            .map(\.text)
            .joined(separator: "\n")
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }
        if let r = Range(match.range, in: text) {
            return String(text[r])
        }
        return nil
    }
}
