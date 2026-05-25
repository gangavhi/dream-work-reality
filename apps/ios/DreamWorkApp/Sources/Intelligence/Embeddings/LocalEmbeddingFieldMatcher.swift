import Foundation

/// Offline embedding-style label matcher. Today this is a deterministic token-vector cosine
/// matcher; the MiniLM/CoreML slot can replace `vector(for:)` without changing callers.
enum LocalEmbeddingFieldMatcher {
    static func canonicalKey(for label: String) -> String? {
        let normalized = label.lowercased()
        let candidates: [(String, [String])] = [
            (ProfileFieldKey.legalFirstName, ["given name", "first name", "forename", "legal first"]),
            (ProfileFieldKey.legalLastName, ["surname", "family name", "last name", "legal family"]),
            (ProfileFieldKey.displayName, ["full legal name", "name of applicant", "cardholder name"]),
            (ProfileFieldKey.dateOfBirth, ["date of birth", "birth date", "dob"]),
            (ProfileFieldKey.addressLine1, ["mailing address", "mailing street", "residential address", "service address", "street address"]),
            (ProfileFieldKey.email, ["email address", "e-mail"]),
            (ProfileFieldKey.phoneMobile, ["phone number", "mobile phone", "telephone"]),
            (ProfileFieldKey.passportNumber, ["passport number", "document number"]),
            (ProfileFieldKey.driversLicenseNumber, ["driver license number", "license number", "dl number"]),
            (ProfileFieldKey.insuranceMemberId, ["member id", "subscriber id", "policy id"]),
            (ProfileFieldKey.employerName, ["employer name", "company", "organization"]),
            (ProfileFieldKey.ssn, ["social security number", "ssn", "taxpayer id"]),
        ]

        let labelVector = vector(for: normalized)
        var best: (key: String, score: Double)?
        for (key, phrases) in candidates {
            for phrase in phrases {
                let score = cosine(labelVector, vector(for: phrase))
                if score >= 0.68, best == nil || score > best!.score {
                    best = (key, score)
                }
            }
        }
        return best?.key
    }

    private static func vector(for text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        for token in tokens {
            out[token, default: 0] += 1
            if token.hasSuffix("s") {
                out[String(token.dropLast()), default: 0] += 0.4
            }
        }
        return out
    }

    private static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let keys = Set(a.keys).union(b.keys)
        let dot = keys.reduce(0) { $0 + (a[$1, default: 0] * b[$1, default: 0]) }
        let normA = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
