import Foundation

/// Maps OCR text to profile fields via OpenAI-compatible API (direct from device — no core-api port-forward).
enum GenAIFieldMapper {
    private static let defaultBaseURL = "https://api.openai.com/v1"
    private static let defaultModel = "gpt-4o-mini"

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

    /// Flat canonical field map from the model.
    static func mapFields(
        ocrText: String,
        documentType: ScannedDocumentType,
        profileSchemaKeys: [String],
        apiKey: String
    ) async -> [OcrFieldSuggestion]? {
        guard let values = await fetchFlatFieldMap(
            ocrText: ocrText,
            documentType: documentType,
            profileSchemaKeys: profileSchemaKeys,
            apiKey: apiKey
        ) else {
            return nil
        }
        return suggestions(from: values)
    }

    /// Driver-license pipeline helper (barcode + OCR text).
    static func mapDriverLicense(
        from rawText: String,
        apiKey: String
    ) async -> DriverLicenseScanResult? {
        guard let values = await fetchFlatFieldMap(
            ocrText: rawText,
            documentType: .driversLicense,
            profileSchemaKeys: ProfileSchema.allFields.map(\.key),
            apiKey: apiKey
        ) else {
            return nil
        }
        return driverLicenseResult(from: values, rawText: rawText)
    }

    private static func fetchFlatFieldMap(
        ocrText: String,
        documentType: ScannedDocumentType,
        profileSchemaKeys: [String],
        apiKey: String
    ) async -> [String: String]? {
        let trimmed = String(ocrText.prefix(24_000))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let baseURL = ProcessInfo.processInfo.environment["DREAMWORK_OPENAI_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["OPENAI_BASE_URL"]
            ?? defaultBaseURL
        let model = ProcessInfo.processInfo.environment["DREAMWORK_OPENAI_MODEL"]
            ?? ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? defaultModel

        let keysList = profileSchemaKeys.joined(separator: ", ")
        let system = """
        You extract structured identity fields from noisy OCR text. Return ONE JSON object only.
        Keys must be from this allow-list when applicable: \(keysList).

        Rules:
        - For US driver's licenses: set display_name to the full name printed on the card (the driver's name).
        - Split name into legal_first_name, legal_middle_name (if any), legal_last_name when visible.
        - Dates use MM/DD/YYYY (date_of_birth, drivers_license_issue_date, drivers_license_expiry).
        - address_line1 is street line only; city, state (2-letter US), postal_code on separate keys.
        - drivers_license_number is the DL ID on the card (not the internal document control number unless that is the only ID).
        - Do not invent values. Omit keys you cannot read.
        - Fix obvious OCR character errors only when confident.
        """

        let user = "Document type hint: \(documentType.rawValue)\n\nOCR text:\n\(trimmed)"

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
            return parseJSONObject(content)
        } catch {
            return nil
        }
    }

    static func suggestions(from values: [String: String]) -> [OcrFieldSuggestion] {
        var out: [OcrFieldSuggestion] = []
        for (rawKey, rawValue) in values {
            let key = normalizeKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            let label = ProfileSchema.definition(for: key)?.label ?? key
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label,
                    value: value,
                    confidence: "High"
                )
            )
        }
        return finalizeSuggestions(out)
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
                byKey[ProfileFieldKey.displayName] = OcrFieldSuggestion(
                    profileKey: ProfileFieldKey.displayName,
                    label: "Display name",
                    value: parts.joined(separator: " "),
                    confidence: "High"
                )
            }
        }

        return byKey.values.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    static func driverLicenseResult(from values: [String: String], rawText: String) -> DriverLicenseScanResult {
        func pick(_ keys: [String]) -> String? {
            for k in keys {
                let canon = normalizeKey(k)
                if let v = values[canon] ?? values[k],
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

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
            state: pick(["drivers_license_state", "state"]),
            postalCode: pick(["postal_code", "zip"]),
            height: pick(["height"]),
            eyeColor: pick(["eye_color"]),
            genAIValues: values,
            rawText: rawText
        )
    }

    private static func parseJSONObject(_ content: String) -> [String: String]? {
        let stripped = stripMarkdownFence(content)
        guard let data = stripped.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        var out: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out[normalizeKey(k)] = t }
            } else if let n = v as? NSNumber {
                out[normalizeKey(k)] = n.stringValue
            }
        }
        return out.isEmpty ? nil : out
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
        default: return k
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
