import Foundation

/// Semantic label → canonical profile key without static rules only (MiniLM/CoreML embedder slot TBD).
enum SemanticFieldLabelMapper {
    private static let synonymGroups: [(keys: [String], profileKey: String)] = [
        (["surname", "family name", "last name", "familyname"], ProfileFieldKey.legalLastName),
        (["given name", "first name", "forename", "legal name", "legal first"], ProfileFieldKey.legalFirstName),
        (["full name", "name", "display name", "cardholder"], ProfileFieldKey.displayName),
        (["dob", "date of birth", "birth date", "birthdate"], ProfileFieldKey.dateOfBirth),
        (["ssn", "social security number", "social security"], ProfileFieldKey.ssn),
        (["member id", "member number", "subscriber id"], ProfileFieldKey.insuranceMemberId),
        (["policy number", "policy no", "policy #"], ProfileFieldKey.insuranceMemberId),
        (["passport no", "passport number", "passport #"], ProfileFieldKey.passportNumber),
        (["dl no", "license number", "driver license", "drivers license number"], ProfileFieldKey.driversLicenseNumber),
        (["vin", "vehicle id"], "vehicle_vin"),
        (["employer", "company name"], ProfileFieldKey.employerName),
    ]

    /// Maps a raw OCR label to the best canonical key using token overlap (embedding model replaces this when `embed.minilm.v1` loads).
    static func canonicalKey(for rawLabel: String) -> String? {
        let normalized = normalize(rawLabel)
        guard !normalized.isEmpty else { return nil }

        var best: (key: String, score: Double)?
        for group in synonymGroups {
            for synonym in group.keys {
                let score = similarity(normalized, normalize(synonym))
                if score >= 0.72, best == nil || score > best!.score {
                    best = (group.profileKey, score)
                }
            }
        }
        return best?.key
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.contains(b) || b.contains(a) { return 0.85 }
        let ta = Set(a.split(separator: " ").map(String.init))
        let tb = Set(b.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let inter = Double(ta.intersection(tb).count)
        let union = Double(ta.union(tb).count)
        return inter / union
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
