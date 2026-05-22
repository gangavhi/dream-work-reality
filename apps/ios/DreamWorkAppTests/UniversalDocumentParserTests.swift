import XCTest
@testable import DreamWorkApp

final class UniversalDocumentParserTests: XCTestCase {
    func testExtractsSSNCardFieldsOnTwoLines() {
        let text = """
        SOCIAL SECURITY
        Jane
        Smith
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
    }

    func testExtractsSSNCardFields() {
        let text = """
        SOCIAL SECURITY
        THIS NUMBER HAS BEEN ESTABLISHED FOR
        Jane Smith
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.ssn], "123-45-6789")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
    }

    func testExtractsDOBFromLabeledLine() {
        let text = """
        Jane Smith
        DOB: 03/15/1985
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let dob = suggestions.first(where: { $0.profileKey == ProfileFieldKey.dateOfBirth })?.value
        XCTAssertEqual(dob, "03/15/1985")
    }

    func testDoesNotBleedDriverLicenseParserOnDLKeywords() {
        let text = DriverLicenseParserTests.texasSampleOCRText
        let suggestions = UniversalDocumentParser.parse(from: text)
        let keys = Set(suggestions.map(\.profileKey))

        XCTAssertFalse(keys.contains(ProfileFieldKey.driversLicenseNumber))
        XCTAssertFalse(keys.contains(ProfileFieldKey.driversLicenseState))
    }

    func testEstimatedFieldsTagged() {
        let suggestions = UniversalDocumentParser.parse(from: "Jane Smith\n123-45-6789")
        XCTAssertTrue(suggestions.allSatisfy { $0.mappingSource == .estimated })
        XCTAssertTrue(suggestions.allSatisfy { $0.confidence == "Estimated" })
    }
}
