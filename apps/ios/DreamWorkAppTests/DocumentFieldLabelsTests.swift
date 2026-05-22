import XCTest
@testable import DreamWorkApp

final class DocumentFieldLabelsTests: XCTestCase {
    func testTexasDriverLicenseNumberLabel() {
        let context = DocumentFieldLabelContext(
            documentType: .driversLicense,
            issuerRegion: "TX",
            country: "US"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseNumber, context: context),
            "Driver License No"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseIssueDate, context: context),
            "Issue Date"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseExpiry, context: context),
            "Expiry Date"
        )
    }

    func testCaliforniaDriverLicenseNumberLabel() {
        let context = DocumentFieldLabelContext(
            documentType: .driversLicense,
            issuerRegion: "CA",
            country: "US"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseNumber, context: context),
            "DL No"
        )
    }

    func testUKDrivingLicenceLabels() {
        let context = DocumentFieldLabelContext(
            documentType: .driversLicense,
            issuerRegion: nil,
            country: "GB"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseNumber, context: context),
            "Driving Licence No"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseIssueDate, context: context),
            "Valid from"
        )
        XCTAssertEqual(
            DocumentFieldLabels.label(for: ProfileFieldKey.driversLicenseExpiry, context: context),
            "Valid to"
        )
    }

    func testDriverLicenseFieldMapperUsesTexasLabel() {
        let scan = DriverLicenseScanResult(
            fullName: "Jane Smith",
            firstName: "Jane",
            middleName: nil,
            lastName: "Smith",
            dateOfBirth: nil,
            documentNumber: "D12345678",
            issueDate: nil,
            expiryDate: nil,
            addressLine1: nil,
            city: nil,
            state: "TX",
            postalCode: nil,
            height: nil,
            eyeColor: nil,
            genAIValues: nil,
            rawText: ""
        )
        let suggestions = DriverLicenseFieldMapper.suggestions(from: scan)
        let dlLabel = suggestions.first { $0.profileKey == ProfileFieldKey.driversLicenseNumber }?.label
        XCTAssertEqual(dlLabel, "Driver License No")
    }
}
