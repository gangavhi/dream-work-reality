import Foundation

struct DocumentClassification: Hashable {
    let documentType: ScannedDocumentType
    let confidence: Double
    let matchedSignals: [String]
}

/// Keyword/heuristic document type detection from OCR text (offline, cost-free).
enum DocumentTypeClassifier {
    private static let fullConfidence = 1.0

    static func classify(from ocrText: String) -> DocumentClassification {
        classifyHeuristic(from: ocrText)
    }

    /// Boosts classification to 100% when structured extraction confirms the detected type.
    static func refine(
        _ classification: DocumentClassification,
        driverLicenseScan: DriverLicenseScanResult?,
        fullText: String
    ) -> DocumentClassification {
        if let confirmed = confirmedDriversLicense(
            classification: classification,
            driverLicenseScan: driverLicenseScan,
            fullText: fullText
        ) {
            return confirmed
        }

        if classification.confidence >= 0.85 {
            return DocumentClassification(
                documentType: classification.documentType,
                confidence: fullConfidence,
                matchedSignals: classification.matchedSignals + ["strong keyword match"]
            )
        }

        return classification
    }

    static func mapToUnderstandingType(_ type: ScannedDocumentType) -> String {
        switch type {
        case .driversLicense: return "drivers_license"
        case .passport: return "passport"
        case .stateId: return "state_id"
        case .insuranceCard: return "insurance_card"
        case .utilityBill: return "utility_bill"
        case .bankStatement: return "bank_statement"
        case .taxDocument: return "tax_form"
        case .employmentDocument: return "employment_document"
        case .ssnCard: return "ssn_card"
        case .other: return "other"
        }
    }

    // MARK: - Heuristic classification

    private static func classifyHeuristic(from ocrText: String) -> DocumentClassification {
        let text = ocrText.uppercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DocumentClassification(documentType: .other, confidence: 0.45, matchedSignals: ["no OCR text"])
        }

        if let vital = detectVitalRecord(in: text) { return vital }
        if let passport = detectPassport(in: text) { return passport }
        if let stateId = detectStateId(in: text) { return stateId }
        if let dl = detectDriversLicense(in: text) { return dl }
        if let insurance = detectInsuranceCard(in: text) { return insurance }
        if let utility = detectUtilityBill(in: text) { return utility }
        if let bank = detectBankStatement(in: text) { return bank }
        if let tax = detectTaxDocument(in: text) { return tax }
        if let employment = detectEmploymentDocument(in: text) { return employment }
        if let ssn = detectSSNCard(in: text) { return ssn }

        return DocumentClassification(documentType: .other, confidence: 0.5, matchedSignals: ["no strong signals"])
    }

    private static func detectSSNCard(in text: String) -> DocumentClassification? {
        guard UniversalDocumentParser.looksLikeSSNDocument(text) else { return nil }
        var signals: [String] = []
        if text.contains("SOCIAL SECURITY") || text.contains("YOUR SOCIAL SECURITY CARD") {
            signals.append("Social Security header")
        }
        if text.contains("ESTABLISHED FOR") || text.range(of: #"(?i)LOCIAL\s+SEC"#, options: .regularExpression) != nil {
            signals.append("SSA stub layout")
        }
        if text.range(of: #"\d{3}-\d{2}-\d{4}"#, options: .regularExpression) != nil {
            signals.append("SSN number format")
        }
        let confidence = signals.count >= 2 ? fullConfidence : 0.9
        return DocumentClassification(documentType: .ssnCard, confidence: confidence, matchedSignals: signals)
    }

    private static func detectVitalRecord(in text: String) -> DocumentClassification? {
        if text.contains("CERTIFICATE OF LIVE BIRTH")
            || (text.contains("BIRTH") && text.contains("CERTIFICATE") && text.contains("LIVE"))
        {
            return DocumentClassification(
                documentType: .other,
                confidence: 0.92,
                matchedSignals: ["birth certificate"]
            )
        }
        if text.contains("CERTIFICATE OF MARRIAGE")
            || (text.contains("MARRIAGE") && text.contains("CERTIFICATE"))
        {
            return DocumentClassification(
                documentType: .other,
                confidence: 0.92,
                matchedSignals: ["marriage certificate"]
            )
        }
        return nil
    }

    private static func detectDriversLicense(in text: String) -> DocumentClassification? {
        let hasDriverHeader = text.contains("DRIVER") || text.contains("OPERATOR")
        let hasLicenseHeader = text.contains("LICENSE") || text.contains("LICENCE")
        if text.contains("IDENTIFICATION CARD"), !hasDriverHeader, !hasLicenseHeader {
            return nil
        }
        let hasDLField = text.range(of: #"(?i)4\s*D\.?\s*DL"#, options: .regularExpression) != nil
            || text.contains("DL:")
        let hasStateIssuer = text.range(
            of: #"\b(TEXAS|CALIFORNIA|FLORIDA|NEW YORK|GEORGIA|OHIO|PENNSYLVANIA|ILLINOIS|MICHIGAN)\b"#,
            options: .regularExpression
        ) != nil
        let hasNumberedNameFields = text.range(of: #"(?i)^\s*[12]\.\s+[A-Z]"#, options: .regularExpression) != nil
            || (text.contains("\n1.") && text.contains("\n2."))

        var signals: [String] = []
        if hasDriverHeader && hasLicenseHeader { signals.append("driver license header") }
        if hasDLField { signals.append("DL number field (4d)") }
        if hasStateIssuer { signals.append("state issuer") }
        if hasNumberedNameFields { signals.append("numbered name fields") }
        if text.contains("CLASS ") { signals.append("license class") }

        guard !signals.isEmpty else { return nil }

        let confidence: Double
        if (hasDriverHeader && hasLicenseHeader && (hasDLField || hasStateIssuer))
            || (hasDriverHeader && hasLicenseHeader && hasNumberedNameFields)
        {
            confidence = fullConfidence
        } else if hasDriverHeader && hasLicenseHeader {
            confidence = 0.92
        } else {
            confidence = 0.75
        }

        return DocumentClassification(
            documentType: .driversLicense,
            confidence: confidence,
            matchedSignals: signals
        )
    }

    private static func detectPassport(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("PASSPORT") { signals.append("passport header") }
        if text.contains("REPUBLIC OF INDIA") || text.contains("GOVERNMENT OF INDIA") {
            signals.append("Republic of India")
        }
        if text.contains("INDIAN") && text.contains("PASSPORT") { signals.append("Indian passport") }
        if text.contains("NATIONALITY") { signals.append("nationality field") }
        if text.contains("P<IND") || text.range(of: #"(?i)<IND\d{6}"#, options: .regularExpression) != nil {
            signals.append("MRZ line")
        }
        if text.contains("P<") && !signals.contains("MRZ line") { signals.append("MRZ line") }

        guard !signals.isEmpty else { return nil }
        let confidence = signals.count >= 2 || text.contains("P<") ? fullConfidence : 0.88
        return DocumentClassification(documentType: .passport, confidence: confidence, matchedSignals: signals)
    }

    private static func detectStateId(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("STATE ID") { signals.append("state ID header") }
        if text.contains("IDENTIFICATION CARD") { signals.append("identification card") }
        if text.contains("NON-DRIVER") { signals.append("non-driver ID") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .stateId,
            confidence: signals.count >= 2 ? fullConfidence : 0.88,
            matchedSignals: signals
        )
    }

    private static func detectInsuranceCard(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("MEMBER") { signals.append("member ID") }
        if text.contains("SUBSCRIBER") { signals.append("subscriber") }
        if text.contains("RXBIN") { signals.append("RX BIN") }
        if text.contains("GROUP #") || text.contains("GROUP#") { signals.append("group number") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .insuranceCard,
            confidence: signals.count >= 2 ? fullConfidence : 0.85,
            matchedSignals: signals
        )
    }

    private static func detectUtilityBill(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("UTILITY") { signals.append("utility") }
        if text.contains("ELECTRIC") { signals.append("electric") }
        if text.contains("KWH") { signals.append("kWh usage") }
        if text.contains("WATER BILL") { signals.append("water bill") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .utilityBill,
            confidence: signals.count >= 2 ? fullConfidence : 0.85,
            matchedSignals: signals
        )
    }

    private static func detectBankStatement(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("ACCOUNT STATEMENT") || text.contains("STATEMENT OF ACCOUNT") {
            signals.append("account statement")
        }
        if text.contains("BANK STATEMENT") { signals.append("bank statement") }
        if text.contains("ROUTING") { signals.append("routing number") }
        if text.contains("DEPOSIT") { signals.append("deposit") }
        if text.contains("BALANCE") { signals.append("balance") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .bankStatement,
            confidence: signals.count >= 2 ? fullConfidence : 0.82,
            matchedSignals: signals
        )
    }

    private static func detectTaxDocument(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("W-2") || text.contains("W2 ") { signals.append("W-2") }
        if text.contains("1099") { signals.append("1099") }
        if text.contains("FORM 1040") { signals.append("Form 1040") }
        if text.contains(" IRS") || text.hasPrefix("IRS") { signals.append("IRS") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .taxDocument,
            confidence: fullConfidence,
            matchedSignals: signals
        )
    }

    private static func detectEmploymentDocument(in text: String) -> DocumentClassification? {
        var signals: [String] = []
        if text.contains("PAYSTUB") || text.contains("PAY STUB") { signals.append("pay stub") }
        if text.contains("EARNINGS") { signals.append("earnings") }
        if text.contains("EMPLOYER") { signals.append("employer") }

        guard !signals.isEmpty else { return nil }
        return DocumentClassification(
            documentType: .employmentDocument,
            confidence: signals.count >= 2 ? fullConfidence : 0.82,
            matchedSignals: signals
        )
    }

    // MARK: - Structured confirmation

    private static func confirmedDriversLicense(
        classification: DocumentClassification,
        driverLicenseScan: DriverLicenseScanResult?,
        fullText: String
    ) -> DocumentClassification? {
        let lines = fullText.components(separatedBy: .newlines)
        let texasParsed = TexasDriverLicenseParser.parse(from: lines, joined: fullText) != nil

        if let dl = driverLicenseScan {
            let fromBarcode = dl.rawText.uppercased().contains("BARCODE:")
            let hasDocumentNumber = dl.documentNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasName = (dl.firstName != nil && dl.lastName != nil) || dl.fullName != nil
            let hasDOB = dl.dateOfBirth != nil

            if fromBarcode {
                return DocumentClassification(
                    documentType: .driversLicense,
                    confidence: fullConfidence,
                    matchedSignals: classification.matchedSignals + ["AAMVA barcode"]
                )
            }

            if hasDocumentNumber && (hasName || hasDOB) {
                var signals = classification.matchedSignals
                if texasParsed { signals.append("Texas DL field layout") }
                signals.append("structured ID extraction")
                return DocumentClassification(
                    documentType: .driversLicense,
                    confidence: fullConfidence,
                    matchedSignals: signals
                )
            }
        }

        if texasParsed {
            return DocumentClassification(
                documentType: .driversLicense,
                confidence: fullConfidence,
                matchedSignals: classification.matchedSignals + ["Texas DL field layout"]
            )
        }

        if classification.documentType == .driversLicense && classification.confidence >= fullConfidence {
            return classification
        }

        return nil
    }
}
