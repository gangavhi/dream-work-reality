import Foundation

/// Maps [`DriverLicenseScanResult`] into canonical `ProfileFieldKey` suggestions for scan review.
enum DriverLicenseFieldMapper {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df
    }()

    static func suggestions(from scan: DriverLicenseScanResult) -> [OcrFieldSuggestion] {
        let labelContext = DocumentFieldLabelContext.from(scan: scan, documentType: .driversLicense)
        var genAILabels: [String: String] = [:]
        if let genAI = scan.genAIValues {
            for (key, value) in genAI where key.hasPrefix("__label_") {
                let profileKey = String(key.dropFirst("__label_".count))
                genAILabels[profileKey] = value
            }
        }
        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ value: String?, _ confidence: String, _ score: Double? = nil) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            let trimmedLabel = genAILabels[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = trimmedLabel.isEmpty
                ? DocumentFieldLabels.label(for: key, context: labelContext)
                : trimmedLabel
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

        let first = scan.firstName.map { DriverLicenseFormatting.personName($0) }
        let middle = scan.middleName.map { DriverLicenseFormatting.personName($0) }
        let last = scan.lastName.map { DriverLicenseFormatting.personName($0) }
        let displayName: String?
        if let first, let last, !first.isEmpty, !last.isEmpty {
            displayName = DriverLicenseFormatting.displayName(first: first, middle: middle, last: last)
        } else {
            displayName = scan.fullName.map { DriverLicenseFormatting.personName($0) }
        }

        add(ProfileFieldKey.displayName, displayName, "High", 0.95)
        add(ProfileFieldKey.legalFirstName, first, "High", 0.95)
        add(ProfileFieldKey.legalMiddleName, middle, "Medium")
        add(ProfileFieldKey.legalLastName, last, "High", 0.95)

        if let dob = scan.dateOfBirth {
            add(ProfileFieldKey.dateOfBirth, formatDate(dob), "High", 0.95)
        }
        add(ProfileFieldKey.driversLicenseNumber, scan.documentNumber, "High", 0.95)
        let dlState = scan.state ?? "TX"
        add(ProfileFieldKey.driversLicenseState, dlState, "High", 0.9)
        if let issue = scan.issueDate {
            add(ProfileFieldKey.driversLicenseIssueDate, formatDate(issue), "High", 0.92)
        }
        if let expiry = scan.expiryDate {
            add(ProfileFieldKey.driversLicenseExpiry, formatDate(expiry), "High", 0.92)
        }
        add(
            ProfileFieldKey.addressLine1,
            scan.addressLine1.map { DriverLicenseFormatting.streetAddress($0) },
            "High",
            0.9
        )
        add(ProfileFieldKey.city, scan.city.map { DriverLicenseFormatting.city($0) }, "High", 0.9)
        add(ProfileFieldKey.state, scan.state, "High", 0.9)
        add(
            ProfileFieldKey.postalCode,
            scan.postalCode.map { DriverLicenseFormatting.zip5($0) },
            "High",
            0.92
        )

        if let gender = scan.genAIValues?["gender"] ?? scan.genAIValues?["sex"] {
            add(ProfileFieldKey.gender, gender, "Medium", 0.7)
        }

        var seen = Set<String>()
        let unique = out.filter { seen.insert($0.profileKey).inserted }
        return ScanFieldValidator.filter(unique, documentType: .driversLicense)
    }

    static func personRecord(from scan: DriverLicenseScanResult) -> PersonRecord {
        let suggestions = suggestions(from: scan)
        var record = PersonRecord.empty()
        for item in suggestions {
            record = record.withValue(item.value, for: item.profileKey)
        }
        if record.value(for: ProfileFieldKey.displayName).isEmpty,
           let name = DriverLicenseFormatting.displayName(
               first: scan.firstName,
               middle: scan.middleName,
               last: scan.lastName
           )
        {
            record = record.withValue(name, for: ProfileFieldKey.displayName)
        }
        return record
    }

    static func resolvedDisplayName(_ scan: DriverLicenseScanResult) -> String? {
        DriverLicenseFormatting.displayName(
            first: scan.firstName.map { DriverLicenseFormatting.personName($0) },
            middle: scan.middleName.map { DriverLicenseFormatting.personName($0) },
            last: scan.lastName.map { DriverLicenseFormatting.personName($0) }
        ) ?? scan.fullName.map { DriverLicenseFormatting.personName($0) }
    }

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
