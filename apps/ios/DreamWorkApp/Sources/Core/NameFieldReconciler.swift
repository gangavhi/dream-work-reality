import Foundation

/// Keeps display name, legal first name, and legal last name consistent after OCR merges.
enum NameFieldReconciler {
    struct SplitName {
        var first: String
        var middle: String?
        var last: String
    }

    static func reconcile(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })

        let first = byKey[ProfileFieldKey.legalFirstName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let middle = byKey[ProfileFieldKey.legalMiddleName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = byKey[ProfileFieldKey.legalLastName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !first.isEmpty, !last.isEmpty,
           ScanFieldValidator.isPlausibleNameComponent(first),
           ScanFieldValidator.isPlausibleNameComponent(last)
        {
            let computed = DriverLicenseFormatting.displayName(
                first: first,
                middle: middle.isEmpty ? nil : middle,
                last: last
            ) ?? ""
            let existingDisplay = byKey[ProfileFieldKey.displayName]?.value
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingDisplay.isEmpty, !computed.isEmpty {
                let confidence = max(
                    byKey[ProfileFieldKey.legalFirstName]?.confidenceScore ?? 0.9,
                    0.95
                )
                byKey[ProfileFieldKey.displayName] = OcrFieldSuggestion(
                    profileKey: ProfileFieldKey.displayName,
                    label: byKey[ProfileFieldKey.displayName]?.label ?? "Full name",
                    value: computed,
                    confidence: "High",
                    confidenceScore: confidence
                )
            }
        }

        guard let displayRaw = byKey[ProfileFieldKey.displayName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !displayRaw.isEmpty,
            ScanFieldValidator.isPlausiblePersonName(displayRaw)
        else {
            return suggestions
        }

        let parsed = splitDisplayName(displayRaw)
        guard !parsed.first.isEmpty, !parsed.last.isEmpty else { return suggestions }

        let existingFirst = byKey[ProfileFieldKey.legalFirstName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingLast = byKey[ProfileFieldKey.legalLastName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingMiddle = byKey[ProfileFieldKey.legalMiddleName]?.value
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let normalizedDisplay = normalize(displayRaw)
        let normalizedExisting = normalize(
            DriverLicenseFormatting.displayName(
                first: existingFirst.isEmpty ? nil : existingFirst,
                middle: existingMiddle.isEmpty ? nil : existingMiddle,
                last: existingLast.isEmpty ? nil : existingLast
            ) ?? ""
        )
        let normalizedParsed = normalize(
            DriverLicenseFormatting.displayName(
                first: parsed.first,
                middle: parsed.middle,
                last: parsed.last
            ) ?? ""
        )

        guard normalizedParsed == normalizedDisplay else { return suggestions }

        let firstMatches = normalize(existingFirst) == normalize(parsed.first)
        let lastMatches = normalize(existingLast) == normalize(parsed.last)
        let middleMatches = normalize(existingMiddle) == normalize(parsed.middle ?? "")
        guard !firstMatches || !lastMatches || !middleMatches else { return suggestions }

        let displayConfidence = byKey[ProfileFieldKey.displayName]?.confidenceScore ?? 0.9
        func upsert(_ key: String, _ fallbackLabel: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            byKey[key] = OcrFieldSuggestion(
                profileKey: key,
                label: byKey[key]?.label ?? fallbackLabel,
                value: DriverLicenseFormatting.personName(trimmed),
                confidence: "High",
                confidenceScore: displayConfidence
            )
        }

        upsert(ProfileFieldKey.legalFirstName, "Legal first name", parsed.first)
        upsert(ProfileFieldKey.legalLastName, "Legal last name", parsed.last)
        if let middle = parsed.middle, !middle.isEmpty {
            upsert(ProfileFieldKey.legalMiddleName, "Legal middle name", middle)
        }

        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    static func splitDisplayName(_ display: String) -> SplitName {
        let cleaned = display
            .replacingOccurrences(of: #"^\d+\.?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains(",") {
            let parts = cleaned.split(separator: ",", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2 {
                let last = DriverLicenseFormatting.personName(parts[0])
                let rest = parts[1].split(whereSeparator: { $0.isWhitespace }).map(String.init)
                let first = rest.first.map { DriverLicenseFormatting.personName($0) } ?? ""
                let middle = rest.count > 1
                    ? DriverLicenseFormatting.personName(rest.dropFirst().joined(separator: " "))
                    : nil
                return SplitName(first: first, middle: middle, last: last)
            }
        }

        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 2 else {
            return SplitName(first: DriverLicenseFormatting.personName(cleaned), middle: nil, last: "")
        }

        let first = DriverLicenseFormatting.personName(words[0])
        let last = DriverLicenseFormatting.personName(words[words.count - 1])
        let middle = words.count > 2
            ? DriverLicenseFormatting.personName(words.dropFirst().dropLast().joined(separator: " "))
            : nil
        return SplitName(first: first, middle: middle, last: last)
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
