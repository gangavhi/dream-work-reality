import XCTest
@testable import DreamWorkApp

final class PersonProfileMatcherTests: XCTestCase {
    func testDobMatchesAcrossUSAndIndianFormats() {
        XCTAssertTrue(PersonProfileMatcher.dobMatches("06/02/1990", "02/06/1990"))
        XCTAssertTrue(PersonProfileMatcher.dobMatches("03/15/1985", "15/03/1985"))
        XCTAssertFalse(PersonProfileMatcher.dobMatches("03/15/1985", "03/16/1985"))
    }

    func testMatchesExistingProfileFromDobAndLastName() {
        let existing = PersonRecord.empty(id: "person-dl")
            .withValue("Alexander Chen", for: ProfileFieldKey.displayName)
            .withValue("Alexander", for: ProfileFieldKey.legalFirstName)
            .withValue("Chen", for: ProfileFieldKey.legalLastName)
            .withValue("03/15/1985", for: ProfileFieldKey.dateOfBirth)
            .withValue("12345678", for: ProfileFieldKey.driversLicenseNumber)

        let updates: [String: String] = [
            ProfileFieldKey.legalFirstName: "Alexander",
            ProfileFieldKey.legalLastName: "Chen",
            ProfileFieldKey.dateOfBirth: "15/03/1985",
            ProfileFieldKey.passportNumber: "P12345678",
        ]

        let match = PersonProfileMatcher.matchExistingPerson(
            among: [existing],
            fieldUpdates: updates,
            resolution: nil
        )

        XCTAssertEqual(match?.personID, "person-dl")
        XCTAssertTrue(match?.reasons.contains("date_of_birth") ?? false)
        XCTAssertTrue(match?.reasons.contains("legal_last_name") ?? false)
    }

    func testMatchesExistingProfileFromDobAndAddressWhenFirstNameTruncated() {
        let existing = PersonRecord.empty(id: "person-dl")
            .withValue("Alexander Chen", for: ProfileFieldKey.displayName)
            .withValue("Alexander", for: ProfileFieldKey.legalFirstName)
            .withValue("Chen", for: ProfileFieldKey.legalLastName)
            .withValue("03/15/1985", for: ProfileFieldKey.dateOfBirth)
            .withValue("2457 Meadowbrook Ave", for: ProfileFieldKey.addressLine1)
            .withValue("78701", for: ProfileFieldKey.postalCode)

        let updates: [String: String] = [
            ProfileFieldKey.legalFirstName: "Xander",
            ProfileFieldKey.legalLastName: "Chen",
            ProfileFieldKey.dateOfBirth: "03/15/1985",
            ProfileFieldKey.addressLine1: "2457 Meadowbrook Ave",
            ProfileFieldKey.passportNumber: "P12345678",
        ]

        let match = PersonProfileMatcher.matchExistingPerson(
            among: [existing],
            fieldUpdates: updates,
            resolution: nil
        )

        XCTAssertEqual(match?.personID, "person-dl")
    }
}
