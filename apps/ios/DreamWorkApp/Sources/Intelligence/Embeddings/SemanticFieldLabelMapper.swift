import Foundation

/// Semantic label → canonical or extension profile key (MiniLM/CoreML embedder slot TBD).
enum SemanticFieldLabelMapper {
    struct ResolvedField: Hashable {
        let profileKey: String
        let displayLabel: String
        let isExtension: Bool
    }

    private static let synonymGroups: [(keys: [String], profileKey: String)] = [
        (["surname", "family name", "last name", "familyname", "sur name"], ProfileFieldKey.legalLastName),
        (["given name", "given names", "first name", "forename", "legal name", "legal first"], ProfileFieldKey.legalFirstName),
        (["full name", "name", "display name", "cardholder", "patient name", "account holder"], ProfileFieldKey.displayName),
        (["dob", "date of birth", "birth date", "birthdate"], ProfileFieldKey.dateOfBirth),
        (["date of issue", "issue date"], ProfileFieldKey.driversLicenseIssueDate),
        (["date of expiry", "date of expiration", "expiry date", "expiration date", "valid until"], ProfileFieldKey.passportExpiry),
        (["due date", "payment due"], "due_date"),
        (["amount due", "total due", "balance due"], "amount_due"),
        (["account number", "acct no", "acct #"], "account_number"),
        (["service address", "billing address", "mailing address"], ProfileFieldKey.addressLine1),
        (["nationality", "country of citizenship"], ProfileFieldKey.passportCountry),
        (["place of birth", "birth place", "pob"], "place_of_birth"),
        (["place of issue", "issued at", "poi"], "place_of_issue"),
        (["sex", "gender"], ProfileFieldKey.gender),
        (["ssn", "social security number", "social security"], ProfileFieldKey.ssn),
        (["member id", "member number", "subscriber id"], ProfileFieldKey.insuranceMemberId),
        (["policy number", "policy no", "policy #"], ProfileFieldKey.insuranceMemberId),
        (["passport no", "passport number", "passport #"], ProfileFieldKey.passportNumber),
        (["dl no", "license number", "driver license", "drivers license number", "lic no"], ProfileFieldKey.driversLicenseNumber),
        (["vin", "vehicle id"], "vehicle_vin"),
        (["employer", "company name"], ProfileFieldKey.employerName),
        (["provider", "utility company", "carrier"], ProfileFieldKey.utilityProvider),
        (["address", "street", "residence"], ProfileFieldKey.addressLine1),
        (["city", "town"], ProfileFieldKey.city),
        (["state", "province"], ProfileFieldKey.state),
        (["zip", "postal", "postal code"], ProfileFieldKey.postalCode),
        (["country"], ProfileFieldKey.country),
        (["email", "e-mail"], ProfileFieldKey.email),
        (["phone", "mobile", "cell", "telephone"], ProfileFieldKey.phoneMobile),
        (["tax year", "year"], ProfileFieldKey.taxYear),
        (["form type", "document type"], ProfileFieldKey.taxFormType),
    ]

    /// Maps label to canonical key when confident; otherwise returns a stable extension key.
    static func resolve(label rawLabel: String, documentTypeHint: String? = nil) -> ResolvedField? {
        let trimmedLabel = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return nil }

        if let key = canonicalKey(for: trimmedLabel) {
            let display = ProfileSchema.definition(for: key)?.label
                ?? ProfileSchema.label(forExtensionKey: key)
            return ResolvedField(profileKey: key, displayLabel: display, isExtension: !ProfileSchema.isCanonicalKey(key))
        }

        let extensionKey = extensionKey(from: trimmedLabel)
        guard isValidExtensionKey(extensionKey) else { return nil }
        _ = documentTypeHint
        return ResolvedField(
            profileKey: extensionKey,
            displayLabel: trimmedLabel.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
            isExtension: true
        )
    }

    /// Maps a raw OCR label to the best canonical key using token overlap.
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

    static func extensionKey(from label: String) -> String {
        var slug = label
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "(s)", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.count > 64 {
            slug = String(slug.prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        return slug
    }

    static func isValidExtensionKey(_ key: String) -> Bool {
        guard key.count >= 2, key.count <= 64 else { return false }
        return key.range(of: #"^[a-z][a-z0-9_]*$"#, options: .regularExpression) != nil
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
            .replacingOccurrences(of: "(s)", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
