import XCTest
@testable import DreamWorkApp

/// Ensures scans for different household members route to separate profiles.
final class HouseholdProfileResolutionTests: XCTestCase {
    private enum Household {
        static let jane = PersonRecord.empty(id: "jane")
            .withValue("Jane Doe", for: ProfileFieldKey.displayName)
            .withValue("Jane", for: ProfileFieldKey.legalFirstName)
            .withValue("Doe", for: ProfileFieldKey.legalLastName)
            .withValue("03/15/1985", for: ProfileFieldKey.dateOfBirth)
            .withValue("D11111111", for: ProfileFieldKey.driversLicenseNumber)
            .withValue("100 Main St", for: ProfileFieldKey.addressLine1)
            .withValue("78701", for: ProfileFieldKey.postalCode)

        static let john = PersonRecord.empty(id: "john")
            .withValue("John Smith", for: ProfileFieldKey.displayName)
            .withValue("John", for: ProfileFieldKey.legalFirstName)
            .withValue("Smith", for: ProfileFieldKey.legalLastName)
            .withValue("06/01/1980", for: ProfileFieldKey.dateOfBirth)
            .withValue("123-45-6789", for: ProfileFieldKey.ssn)
            .withValue("100 Main St", for: ProfileFieldKey.addressLine1)
            .withValue("78701", for: ProfileFieldKey.postalCode)

        static let emma = PersonRecord.empty(id: "emma")
            .withValue("Emma Smith", for: ProfileFieldKey.displayName)
            .withValue("Emma", for: ProfileFieldKey.legalFirstName)
            .withValue("Smith", for: ProfileFieldKey.legalLastName)
            .withValue("09/10/2012", for: ProfileFieldKey.dateOfBirth)
            .withValue("987654321", for: ProfileFieldKey.stateIdNumber)
    }

    func testJaneBirthCertificateMatchesJaneNotJohn() {
        let people = [Household.jane, Household.john]
        let updates = birthCertificateFields(for: "Jane", "Doe", dob: "03/15/1985")

        let match = PersonProfileMatcher.matchExistingPerson(
            among: people,
            fieldUpdates: updates,
            resolution: nil
        )

        XCTAssertEqual(match?.personID, "jane")
        XCTAssertTrue(PersonProfileMatcher.hasIdentityConflict(person: Household.john, fieldUpdates: updates))
    }

    func testJohnSSNMatchesJohnNotJane() {
        let people = [Household.jane, Household.john]
        let updates: [String: String] = [
            ProfileFieldKey.legalFirstName: "John",
            ProfileFieldKey.legalLastName: "Smith",
            ProfileFieldKey.ssn: "123-45-6789",
            ProfileFieldKey.postalCode: "78701",
        ]

        let match = PersonProfileMatcher.matchExistingPerson(
            among: people,
            fieldUpdates: updates,
            resolution: nil
        )

        XCTAssertEqual(match?.personID, "john")
    }

    func testDifferentDriversLicenseCreatesNewProfileNotJane() {
        let people = [Household.jane, Household.john]
        let updates: [String: String] = [
            ProfileFieldKey.legalFirstName: "Emma",
            ProfileFieldKey.legalLastName: "Smith",
            ProfileFieldKey.dateOfBirth: "09/10/2012",
            ProfileFieldKey.driversLicenseNumber: "D99999999",
            ProfileFieldKey.postalCode: "78701",
            ProfileFieldKey.addressLine1: "100 Main St",
        ]

        let match = PersonProfileMatcher.matchExistingPerson(
            among: people,
            fieldUpdates: updates,
            resolution: nil
        )

        XCTAssertNil(match)
        XCTAssertTrue(PersonProfileMatcher.hasIdentityConflict(person: Household.jane, fieldUpdates: updates))
    }

    func testRustResolverKeepsHouseholdMembersSeparate() {
        let people = [Household.jane, Household.john, Household.emma]

        let janeBirth = CoreIngestFFI.resolvePerson(
            fields: birthCertificateFields(for: "Jane", "Doe", dob: "03/15/1985"),
            people: people
        )
        XCTAssertEqual(janeBirth?.resolution, .matchExisting)
        XCTAssertEqual(janeBirth?.personID, "jane")

        let johnSSN = CoreIngestFFI.resolvePerson(
            fields: [
                ProfileFieldKey.legalFirstName: "John",
                ProfileFieldKey.legalLastName: "Smith",
                ProfileFieldKey.ssn: "123-45-6789",
            ],
            people: people
        )
        XCTAssertEqual(johnSSN?.resolution, .matchExisting)
        XCTAssertEqual(johnSSN?.personID, "john")

        let emmaStateID = CoreIngestFFI.resolvePerson(
            fields: [
                ProfileFieldKey.legalFirstName: "Emma",
                ProfileFieldKey.legalLastName: "Smith",
                ProfileFieldKey.dateOfBirth: "09/10/2012",
                ProfileFieldKey.stateIdNumber: "987654321",
            ],
            people: people
        )
        XCTAssertEqual(emmaStateID?.resolution, .matchExisting)
        XCTAssertEqual(emmaStateID?.personID, "emma")
    }

    func testInsuranceBillWithTexasProviderDoesNotCrashNameResolver() {
        let text = """
        BLUE CROSS BLUE SHIELD OF TEXAS
        MEMBER ID: XYZ987654321
        SUBSCRIBER: JANE DOE
        GROUP #: 12345
        DOB: 03/15/1985
        PLAN: PPO
        """
        let suggestions = OcrFieldSuggester.suggest(from: text, documentType: .insuranceCard)
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.insuranceMemberId })
    }

    func testShortInsuranceOCRDoesNotCrashTexasConsecutiveLines() {
        let text = "BLUE CROSS OF TEXAS"
        let resolved = PersonNameResolver.resolve(from: text, documentType: .insuranceCard)
        XCTAssertNil(resolved)
    }

    private func birthCertificateFields(for first: String, _ last: String, dob: String) -> [String: String] {
        [
            ProfileFieldKey.displayName: "\(first) \(last)",
            ProfileFieldKey.legalFirstName: first,
            ProfileFieldKey.legalLastName: last,
            ProfileFieldKey.dateOfBirth: dob,
            ProfileFieldKey.postalCode: "78701",
            ProfileFieldKey.addressLine1: "100 Main St",
        ]
    }
}
