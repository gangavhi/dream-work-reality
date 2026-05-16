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
        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ label: String, _ value: String?, _ confidence: String) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            out.append(
                OcrFieldSuggestion(profileKey: key, label: label, value: trimmed, confidence: confidence)
            )
        }

        let displayName = resolvedDisplayName(scan)
        add(ProfileFieldKey.displayName, "Display name", displayName, "High")
        add(ProfileFieldKey.legalFirstName, "Legal first name", scan.firstName, "High")
        add(ProfileFieldKey.legalMiddleName, "Legal middle name", scan.middleName, "Medium")
        add(ProfileFieldKey.legalLastName, "Legal last name", scan.lastName, "High")

        if let dob = scan.dateOfBirth {
            add(ProfileFieldKey.dateOfBirth, "Date of birth", formatDate(dob), "High")
        }
        add(ProfileFieldKey.driversLicenseNumber, "Driver license number", scan.documentNumber, "High")
        add(ProfileFieldKey.driversLicenseState, "Driver license state", scan.state, "Medium")
        if let issue = scan.issueDate {
            add(ProfileFieldKey.driversLicenseIssueDate, "Driver license issue date", formatDate(issue), "High")
        }
        if let expiry = scan.expiryDate {
            add(ProfileFieldKey.driversLicenseExpiry, "Driver license expiry", formatDate(expiry), "High")
        }
        add(ProfileFieldKey.addressLine1, "Address line 1", scan.addressLine1, "Medium")
        add(ProfileFieldKey.city, "City", scan.city, "Medium")
        add(ProfileFieldKey.state, "State / province", scan.state, "Medium")
        add(ProfileFieldKey.postalCode, "ZIP / postal code", scan.postalCode, "Medium")

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
           let name = resolvedDisplayName(scan)
        {
            record = record.withValue(name, for: ProfileFieldKey.displayName)
        }
        return record
    }

    static func resolvedDisplayName(_ scan: DriverLicenseScanResult) -> String? {
        if let full = scan.fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            return full
        }
        let parts = [scan.firstName, scan.middleName, scan.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
