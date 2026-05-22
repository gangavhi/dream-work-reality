import XCTest
@testable import DreamWorkApp

final class ProfileSchemaOrderingTests: XCTestCase {
    func testSortSuggestionsGroupsAddressAndLicenseFields() {
        let suggestions = [
            OcrFieldSuggestion(profileKey: ProfileFieldKey.driversLicenseExpiry, label: "Expiry", value: "01/10/2028", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.city, label: "City", value: "Austin", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.legalFirstName, label: "First", value: "Jane", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.driversLicenseNumber, label: "DL#", value: "D12345678", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.addressLine1, label: "Street", value: "742 Oak St", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.driversLicenseIssueDate, label: "Issue", value: "01/10/2023", confidence: "High"),
        ]

        let sorted = ProfileSchema.sortSuggestions(suggestions)
        let keys = sorted.map(\.profileKey)

        XCTAssertEqual(keys.first, ProfileFieldKey.legalFirstName)
        XCTAssertEqual(
            keys.filter {
                [ProfileFieldKey.addressLine1, ProfileFieldKey.city].contains($0)
            },
            [ProfileFieldKey.addressLine1, ProfileFieldKey.city]
        )
        XCTAssertEqual(
            keys.filter {
                [
                    ProfileFieldKey.driversLicenseNumber,
                    ProfileFieldKey.driversLicenseIssueDate,
                    ProfileFieldKey.driversLicenseExpiry,
                ].contains($0)
            },
            [
                ProfileFieldKey.driversLicenseNumber,
                ProfileFieldKey.driversLicenseIssueDate,
                ProfileFieldKey.driversLicenseExpiry,
            ]
        )
    }

    func testGroupedSuggestionsUsesSectionTitles() {
        let suggestions = [
            OcrFieldSuggestion(profileKey: ProfileFieldKey.ssn, label: "SSN", value: "123-45-6789", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.displayName, label: "Name", value: "Jane Smith", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.driversLicenseNumber, label: "DL#", value: "D12345678", confidence: "High"),
        ]

        let groups = ProfileSchema.groupedSuggestions(suggestions)
        XCTAssertEqual(groups.map(\.title), ["Identity", "Government IDs", "Tax"])
    }
}
