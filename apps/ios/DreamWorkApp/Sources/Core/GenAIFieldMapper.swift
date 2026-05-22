import Foundation

/// Maps OCR text to profile fields via OpenAI-compatible API (OpenAI, Ollama, LM Studio).
enum GenAIFieldMapper {
    struct ExtractionResult {
        var values: [String: String]
        var labels: [String: String]
        var documentType: String?
        var issuerRegion: String?
        var country: String?
    }

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var temperature: Double
        var response_format: ResponseFormat

        struct ResponseFormat: Encodable {
            var type: String = "json_object"
        }

        struct Message: Encodable {
            var role: String
            var content: String
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String
            }
            var message: Message
        }
        var choices: [Choice]
    }

    /// General-purpose extraction from layout-ordered OCR (no document-type routing).
    static func mapFields(
        layoutText: String,
        profileSchemaKeys: [String]
    ) async -> (suggestions: [OcrFieldSuggestion], documentType: String?)? {
        guard let extraction = await fetchExtraction(
            layoutText: layoutText,
            profileSchemaKeys: profileSchemaKeys
        ) else {
            return nil
        }
        let presentation = DocumentTypePresentation.resolve(extraction.documentType)
        return (
            suggestions(from: extraction, documentType: presentation.enumType),
            extraction.documentType
        )
    }

    /// Legacy flat-text entry — prefer `mapFields(layoutText:)`.
    static func mapFields(
        ocrText: String,
        documentType: ScannedDocumentType,
        profileSchemaKeys: [String]
    ) async -> (suggestions: [OcrFieldSuggestion], documentType: String?)? {
        await mapFields(layoutText: ocrText, profileSchemaKeys: profileSchemaKeys)
    }

    /// Driver-license scanner UI helper (legacy surface).
    static func mapDriverLicense(from rawText: String) async -> DriverLicenseScanResult? {
        guard let extraction = await fetchExtraction(
            layoutText: rawText,
            profileSchemaKeys: ProfileSchema.allFields.map(\.key)
        ) else {
            return nil
        }
        return driverLicenseResult(from: extraction, rawText: rawText)
    }

    private static func fetchExtraction(
        layoutText: String,
        profileSchemaKeys: [String]
    ) async -> ExtractionResult? {
        guard let config = GenAISettings.activeLLMConfig else { return nil }
        return await fetchExtraction(
            layoutText: layoutText,
            profileSchemaKeys: profileSchemaKeys,
            baseURL: config.baseURL,
            model: config.model,
            apiKey: config.apiKey
        )
    }

    private static func fetchExtraction(
        layoutText: String,
        profileSchemaKeys: [String],
        baseURL: String,
        model: String,
        apiKey: String
    ) async -> ExtractionResult? {
        let trimmed = String(layoutText.prefix(24_000))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let keysList = profileSchemaKeys.joined(separator: ", ")
        let system = """
        You extract structured fields from OCR text with layout hints. Return ONE JSON object only.

        Response shape (required):
        {
          "document_type": "short snake_case label describing this document (open vocabulary, e.g. drivers_license, school_enrollment_form, medical_bill, green_card, other)",
          "issuer_region": "2-letter US state, province, or region when known, else omit",
          "country": "2-letter ISO country when known, else omit",
          "fields": {
            "<canonical_key>": {"value": "...", "label": "..."},
            ...
          }
        }

        Canonical keys (use when applicable): \(keysList).
        You may add extension keys (snake_case) for clear attributes not in the list.

        Rules:
        - Infer document_type from content; use a specific snake_case label when confident, else "other".
        - Set "label" to the human text printed on the document (Title Case; no invented field numbers).
        - Split person names into legal_first_name, legal_middle_name, legal_last_name when shown; use display_name for full line if needed.
        - Dates as MM/DD/YYYY in value.
        - address_line1 is street only; city, state, postal_code separate when visible.
        - Do not invent values. Omit uncertain fields.
        - Use embedded barcode/MRZ sections when present — they are authoritative over noisy OCR lines.
        """

        let user = "Extract fields from this layout-ordered OCR (blocks and optional machine-readable payloads):\n\n\(trimmed)"

        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        request.httpBody = try? JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: system),
                    .init(role: "user", content: user),
                ],
                temperature: 0.1,
                response_format: .init()
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(status) else { return nil }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else { return nil }
            return parseExtractionJSON(content)
        } catch {
            return nil
        }
    }

    static func suggestions(
        from values: [String: String],
        documentType: ScannedDocumentType = .other
    ) -> [OcrFieldSuggestion] {
        suggestions(
            from: ExtractionResult(values: values, labels: [:], issuerRegion: nil, country: nil),
            documentType: documentType
        )
    }

    static func suggestions(
        from extraction: ExtractionResult,
        documentType: ScannedDocumentType
    ) -> [OcrFieldSuggestion] {
        var fieldValues = extraction.values
        if let region = extraction.issuerRegion?.nilIfEmpty {
            fieldValues[ProfileFieldKey.driversLicenseState] = fieldValues[ProfileFieldKey.driversLicenseState] ?? region
        }
        if let country = extraction.country?.nilIfEmpty {
            fieldValues[ProfileFieldKey.country] = fieldValues[ProfileFieldKey.country] ?? country
        }

        let context = DocumentFieldLabelContext.from(fieldValues: fieldValues, documentType: documentType)
        var out: [OcrFieldSuggestion] = []
        for (rawKey, rawValue) in extraction.values {
            let key = normalizeKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            let label = resolvedLabel(
                for: key,
                genAILabel: extraction.labels[key],
                context: context
            )
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label,
                    value: value,
                    confidence: "High",
                    confidenceScore: 0.88
                )
            )
        }
        return finalizeSuggestions(out, documentType: documentType)
    }

    private static func resolvedLabel(
        for key: String,
        genAILabel: String?,
        context: DocumentFieldLabelContext
    ) -> String {
        if let genAILabel = genAILabel?.trimmingCharacters(in: .whitespacesAndNewlines), !genAILabel.isEmpty {
            return genAILabel
        }
        return DocumentFieldLabels.label(for: key, context: context)
    }

    static func finalizeSuggestions(
        _ input: [OcrFieldSuggestion],
        documentType: ScannedDocumentType = .other
    ) -> [OcrFieldSuggestion] {
        let input = ScanFieldValidator.filter(input, documentType: documentType)
        var byKey = Dictionary(uniqueKeysWithValues: input.map { ($0.profileKey, $0) })

        if byKey[ProfileFieldKey.displayName] == nil {
            let first = byKey[ProfileFieldKey.legalFirstName]?.value
            let middle = byKey[ProfileFieldKey.legalMiddleName]?.value
            let last = byKey[ProfileFieldKey.legalLastName]?.value
            let parts = [first, middle, last]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                let context = DocumentFieldLabelContext.from(
                    suggestions: Array(byKey.values),
                    documentType: documentType
                )
                byKey[ProfileFieldKey.displayName] = OcrFieldSuggestion(
                    profileKey: ProfileFieldKey.displayName,
                    label: resolvedLabel(for: ProfileFieldKey.displayName, genAILabel: nil, context: context),
                    value: parts.joined(separator: " "),
                    confidence: "High",
                    confidenceScore: 0.9
                )
            }
        }

        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    static func driverLicenseResult(from values: [String: String], rawText: String) -> DriverLicenseScanResult {
        driverLicenseResult(
            from: ExtractionResult(values: values, labels: [:], documentType: nil, issuerRegion: nil, country: nil),
            rawText: rawText
        )
    }

    static func driverLicenseResult(from extraction: ExtractionResult, rawText: String) -> DriverLicenseScanResult {
        func pick(_ keys: [String]) -> String? {
            for k in keys {
                let canon = normalizeKey(k)
                if let v = extraction.values[canon] ?? extraction.values[k],
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        var genAIValues = extraction.values
        for (key, label) in extraction.labels where !label.isEmpty {
            genAIValues["__label_\(key)"] = label
        }
        if let region = extraction.issuerRegion { genAIValues["issuer_region"] = region }
        if let country = extraction.country { genAIValues["country"] = country }

        return DriverLicenseScanResult(
            fullName: pick(["display_name", "full_name"]),
            firstName: pick(["legal_first_name", "first_name"]),
            middleName: pick(["legal_middle_name", "middle_name"]),
            lastName: pick(["legal_last_name", "last_name"]),
            dateOfBirth: parseDate(pick(["date_of_birth", "date_of_birth_mmddyyyy", "dob"])),
            documentNumber: pick(["drivers_license_number", "document_number", "dl"]),
            issueDate: parseDate(pick(["drivers_license_issue_date", "issue_mmddyyyy", "issue"])),
            expiryDate: parseDate(pick(["drivers_license_expiry", "expiry_mmddyyyy", "expiry"])),
            addressLine1: pick(["address_line1", "address_line_1"]),
            city: pick(["city"]),
            state: pick(["drivers_license_state", "state"]) ?? extraction.issuerRegion,
            postalCode: pick(["postal_code", "zip"]),
            height: pick(["height"]),
            eyeColor: pick(["eye_color"]),
            genAIValues: genAIValues,
            rawText: rawText
        )
    }

    private static func parseExtractionJSON(_ content: String) -> ExtractionResult? {
        let stripped = stripMarkdownFence(content)
        guard let data = stripped.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let issuerRegion = stringValue(obj["issuer_region"])
        let country = stringValue(obj["country"])
        let documentType = stringValue(obj["document_type"])

        var values: [String: String] = [:]
        var labels: [String: String] = [:]

        if let fields = obj["fields"] as? [String: Any] {
            for (rawKey, rawEntry) in fields {
                let key = normalizeKey(rawKey)
                guard !key.isEmpty else { continue }
                if let entry = rawEntry as? [String: Any] {
                    if let value = stringValue(entry["value"]) {
                        values[key] = value
                    }
                    if let label = stringValue(entry["label"]) {
                        labels[key] = label
                    }
                } else if let flat = stringValue(rawEntry) {
                    values[key] = flat
                }
            }
        }

        // Backward compatibility: flat top-level keys.
        if values.isEmpty {
            for (k, v) in obj where k != "fields" && k != "issuer_region" && k != "country" && k != "document_type" {
                if let s = stringValue(v) {
                    values[normalizeKey(k)] = s
                }
            }
        }

        guard !values.isEmpty else { return nil }
        return ExtractionResult(
            values: values,
            labels: labels,
            documentType: documentType,
            issuerRegion: issuerRegion,
            country: country
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = value as? NSNumber {
            return n.stringValue
        }
        return nil
    }

    private static func normalizeKey(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "_")
        switch k {
        case "first_name", "first": return ProfileFieldKey.legalFirstName
        case "last_name", "last": return ProfileFieldKey.legalLastName
        case "middle_name", "middle": return ProfileFieldKey.legalMiddleName
        case "full_name": return ProfileFieldKey.displayName
        case "dob", "birth_date", "date_of_birth_mmddyyyy": return ProfileFieldKey.dateOfBirth
        case "address_line_1", "addr", "street": return ProfileFieldKey.addressLine1
        case "zip", "zip_code": return ProfileFieldKey.postalCode
        case "document_number", "dl", "license_number", "dl_number": return ProfileFieldKey.driversLicenseNumber
        case "license_state", "dl_state": return ProfileFieldKey.driversLicenseState
        case "issue_mmddyyyy", "issue", "issue_date": return ProfileFieldKey.driversLicenseIssueDate
        case "expiry_mmddyyyy", "expiry", "expiration": return ProfileFieldKey.driversLicenseExpiry
        case "sex", "gender": return ProfileFieldKey.gender
        default:
            let normalized = k
            if ProfileSchema.isCanonicalKey(normalized) { return normalized }
            return normalized
        }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["MM/dd/yyyy", "yyyy-MM-dd"] {
            df.dateFormat = format
            if let d = df.date(from: trimmed) { return d }
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 8 {
            let yyyy = String(digits.prefix(4))
            let mm = String(digits.dropFirst(4).prefix(2))
            let dd = String(digits.dropFirst(6).prefix(2))
            df.dateFormat = "MM/dd/yyyy"
            return df.date(from: "\(mm)/\(dd)/\(yyyy)")
        }
        return nil
    }

    private static func stripMarkdownFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```json") { t = String(t.dropFirst(7)) }
        else if t.hasPrefix("```") { t = String(t.dropFirst(3)) }
        if let end = t.range(of: "```", options: .backwards) {
            t = String(t[..<end.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
