import Foundation

/// Cross-field validation after extraction, before normalization/confidence.
enum DocumentValidationPipeline {
    struct Report: Hashable {
        let suggestions: [OcrFieldSuggestion]
        let rejectedKeys: [String]
        let warnings: [String]
    }

    static func validate(
        _ suggestions: [OcrFieldSuggestion],
        documentType: ScannedDocumentType,
        ocrCorpus: String
    ) -> Report {
        var warnings: [String] = []
        var rejected = Set<String>()

        let shapeFiltered = ScanFieldValidator.filter(suggestions, documentType: documentType)
        let shapeRejected = Set(suggestions.map(\.profileKey)).subtracting(shapeFiltered.map(\.profileKey))
        if !shapeRejected.isEmpty {
            warnings.append("shape_rejected:\(shapeRejected.sorted().joined(separator: ","))")
            rejected.formUnion(shapeRejected)
        }

        var working = shapeFiltered
        let values = Dictionary(uniqueKeysWithValues: working.map { ($0.profileKey, $0.value) })

        if let dob = values[ProfileFieldKey.dateOfBirth], isFutureDate(dob) {
            working.removeAll { $0.profileKey == ProfileFieldKey.dateOfBirth }
            rejected.insert(ProfileFieldKey.dateOfBirth)
            warnings.append("dob_in_future")
        }

        let issueKeys = [ProfileFieldKey.driversLicenseIssueDate, "issue_date"]
        let expiryKeys = [ProfileFieldKey.driversLicenseExpiry, ProfileFieldKey.passportExpiry, ProfileFieldKey.stateIdExpiry, "expiration_date"]
        if let issueRaw = issueKeys.compactMap({ values[$0] }).first,
           let expiryRaw = expiryKeys.compactMap({ values[$0] }).first,
           let issue = parseDate(issueRaw),
           let expiry = parseDate(expiryRaw),
           expiry < issue
        {
            for key in expiryKeys where values[key] != nil {
                working.removeAll { $0.profileKey == key }
                rejected.insert(key)
            }
            warnings.append("expiration_before_issue")
        }

        if documentType == .passport || documentType == .driversLicense {
            if let passport = values[ProfileFieldKey.passportNumber],
               !isPlausiblePassportNumber(passport)
            {
                working.removeAll { $0.profileKey == ProfileFieldKey.passportNumber }
                rejected.insert(ProfileFieldKey.passportNumber)
                warnings.append("invalid_passport_number")
            }
        }

        let grounded = OcrGroundingValidator.filter(working, ocrCorpus: ocrCorpus)
        let groundingRejected = Set(working.map(\.profileKey)).subtracting(grounded.map(\.profileKey))
        if !groundingRejected.isEmpty {
            warnings.append("grounding_rejected:\(groundingRejected.count)")
            rejected.formUnion(groundingRejected)
        }

        return Report(
            suggestions: ProfileSchema.sortSuggestions(grounded),
            rejectedKeys: Array(rejected).sorted(),
            warnings: warnings
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let normalized = FieldNormalizationEngine.normalizeDate(raw)
        let parts = normalized.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func isFutureDate(_ raw: String) -> Bool {
        guard let date = parseDate(raw) else { return false }
        return date > Date()
    }

    private static func isPlausiblePassportNumber(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6 ... 12).contains(trimmed.count) else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }
}
