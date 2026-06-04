import Foundation

/// Merges city / state / postal code from separate OCR lines into address profile fields.
enum AddressFieldMerger {
    static func enrich(
        _ suggestions: [OcrFieldSuggestion],
        layout: LayoutIntelligenceAgent.LayoutDocument
    ) -> [OcrFieldSuggestion] {
        var byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })

        absorbMisplacedCity(from: &byKey)
        fillFromLayoutPairs(&byKey, layout: layout)
        fillFromAdjacentLines(&byKey, layoutText: layout.layoutText)

        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    private static func absorbMisplacedCity(from byKey: inout [String: OcrFieldSuggestion]) {
        guard let address = byKey[ProfileFieldKey.addressLine1] else { return }
        let street = address.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !street.isEmpty else { return }

        if MappedFieldValueValidator.looksLikeStreetAddress(street) { return }

        if MappedFieldValueValidator.looksLikePersonName(street),
           !MappedFieldValueValidator.looksLikeStreetAddress(street),
           byKey[ProfileFieldKey.city] == nil
        {
            byKey[ProfileFieldKey.city] = OcrFieldSuggestion(
                profileKey: ProfileFieldKey.city,
                label: ProfileSchema.definition(for: ProfileFieldKey.city)?.label ?? "City",
                value: street,
                confidence: "Medium",
                confidenceScore: 0.62,
                mappingSource: .onDevice
            )
            byKey.removeValue(forKey: ProfileFieldKey.addressLine1)
        }
    }

    private static func fillFromLayoutPairs(
        _ byKey: inout [String: OcrFieldSuggestion],
        layout: LayoutIntelligenceAgent.LayoutDocument
    ) {
        for pair in layout.labelValuePairs {
            let label = pair.label.lowercased()
            if label.contains("city") {
                upsert(&byKey, key: ProfileFieldKey.city, value: pair.value, score: 0.78)
            } else if label.contains("state") || label == "st" {
                upsert(&byKey, key: ProfileFieldKey.state, value: pair.value, score: 0.78)
            } else if label.contains("zip") || label.contains("postal") {
                upsert(&byKey, key: ProfileFieldKey.postalCode, value: pair.value, score: 0.78)
            }
        }

        for line in layout.layoutText.components(separatedBy: .newlines) {
            guard let parsed = parseCityStateZipLine(line) else { continue }
            if byKey[ProfileFieldKey.city] == nil, let city = parsed.city {
                upsert(&byKey, key: ProfileFieldKey.city, value: city, score: 0.7)
            }
            if byKey[ProfileFieldKey.state] == nil, let state = parsed.state {
                upsert(&byKey, key: ProfileFieldKey.state, value: state, score: 0.7)
            }
            if byKey[ProfileFieldKey.postalCode] == nil, let zip = parsed.postal {
                upsert(&byKey, key: ProfileFieldKey.postalCode, value: zip, score: 0.7)
            }
        }
    }

    private static func fillFromAdjacentLines(
        _ byKey: inout [String: OcrFieldSuggestion],
        layoutText: String
    ) {
        guard byKey[ProfileFieldKey.addressLine1] != nil else { return }
        let lines = layoutText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let streetIndex = lines.firstIndex(where: {
            MappedFieldValueValidator.looksLikeStreetAddress($0)
        }) else { return }

        let tail = lines.dropFirst(streetIndex + 1).prefix(3)
        for line in tail {
            if byKey[ProfileFieldKey.city] == nil,
               line.range(of: #"^[A-Za-z][A-Za-z\s\-'.]{1,40}$"#, options: .regularExpression) != nil,
               !MappedFieldValueValidator.looksLikeStreetAddress(line)
            {
                upsert(&byKey, key: ProfileFieldKey.city, value: line, score: 0.65)
                continue
            }
            if let parsed = parseCityStateZipLine(line) {
                if byKey[ProfileFieldKey.city] == nil, let city = parsed.city {
                    upsert(&byKey, key: ProfileFieldKey.city, value: city, score: 0.68)
                }
                if byKey[ProfileFieldKey.state] == nil, let state = parsed.state {
                    upsert(&byKey, key: ProfileFieldKey.state, value: state, score: 0.68)
                }
                if byKey[ProfileFieldKey.postalCode] == nil, let zip = parsed.postal {
                    upsert(&byKey, key: ProfileFieldKey.postalCode, value: zip, score: 0.68)
                }
            }
        }
    }

    private static func parseCityStateZipLine(_ line: String) -> (city: String?, state: String?, postal: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = trimmed.range(
            of: #"^([A-Za-z][A-Za-z\s\-'.]{1,40}),\s*([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$"#,
            options: .regularExpression
        ) {
            let parts = trimmed[match].split(separator: ",").map(String.init)
            if parts.count == 2 {
                let stateZip = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if stateZip.count >= 2 {
                    return (parts[0].trimmingCharacters(in: .whitespaces), String(stateZip[0]), String(stateZip[1]))
                }
            }
        }

        if let match = trimmed.range(
            of: #"^([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$"#,
            options: .regularExpression
        ) {
            let parts = trimmed[match].split(separator: " ")
            if parts.count >= 2 {
                return (nil, String(parts[0]), String(parts[1]))
            }
        }

        return nil
    }

    private static func upsert(
        _ byKey: inout [String: OcrFieldSuggestion],
        key: String,
        value: String,
        score: Double
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard MappedFieldValueValidator.accepts(profileKey: key, value: trimmed) else { return }

        let label = ProfileSchema.definition(for: key)?.label ?? key
        let candidate = OcrFieldSuggestion(
            profileKey: key,
            label: label,
            value: trimmed,
            confidence: score >= 0.75 ? "High" : "Medium",
            confidenceScore: score,
            mappingSource: .onDevice
        )
        if let existing = byKey[key], existing.confidenceScore >= candidate.confidenceScore {
            return
        }
        byKey[key] = candidate
    }
}
