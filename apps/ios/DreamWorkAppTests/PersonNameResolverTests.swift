import XCTest
@testable import DreamWorkApp

final class PersonNameResolverTests: XCTestCase {
    func testTexasNumberedFieldsProduceCorrectDisplayName() {
        let text = DriverLicenseParserTests.texasSampleOCRText
        let resolved = PersonNameResolver.resolve(from: text, documentType: .driversLicense)
        XCTAssertEqual(resolved?.first, "Jane")
        XCTAssertEqual(resolved?.last, "Smith")
        XCTAssertEqual(resolved?.display, "Jane Smith")
    }

    func testTexasNoisyStandaloneLinesProduceCorrectDisplayName() {
        let text = DriverLicenseParserTests.texasSampleNoisyOCRText
        let resolved = PersonNameResolver.resolve(from: text, documentType: .driversLicense)
        XCTAssertEqual(resolved?.first, "Jane")
        XCTAssertEqual(resolved?.last, "Smith")
        XCTAssertEqual(resolved?.display, "Jane Smith")
    }

    func testExpandsTruncatedFirstNameWhenFullNameAppearsElsewhere() {
        let text = """
        TEXAS
        DRIVER LICENSE
        4d. DL: D12345678
        CHEN
        XANDER
        ALEXANDER
        3. DOB: 03/15/1985
        """
        let resolved = PersonNameResolver.resolve(from: text, documentType: .driversLicense)
        XCTAssertEqual(resolved?.first, "Alexander")
        XCTAssertEqual(resolved?.last, "Chen")
        XCTAssertEqual(resolved?.display, "Alexander Chen")
    }

    func testSingleLineDisplayOrderStillMapsToTexasLastFirst() {
        let text = """
        TEXAS
        DRIVER LICENSE
        XANDER CHEN
        4d. DL: D12345678
        """
        let resolved = PersonNameResolver.resolve(from: text, documentType: .driversLicense)
        XCTAssertEqual(resolved?.first, "Xander")
        XCTAssertEqual(resolved?.last, "Chen")
    }

    func testApplyOverridesWrongGenAIDisplayName() {
        let ocrText = DriverLicenseParserTests.texasSampleNoisyOCRText
        let suggestions = [
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.displayName,
                label: "Full name",
                value: "Smith Jane",
                confidence: "High",
                confidenceScore: 0.99
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalFirstName,
                label: "Legal first name",
                value: "Smith",
                confidence: "High",
                confidenceScore: 0.99
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalLastName,
                label: "Legal last name",
                value: "Jane",
                confidence: "High",
                confidenceScore: 0.99
            ),
        ]

        let fixed = PersonNameResolver.apply(to: suggestions, ocrText: ocrText, documentType: .driversLicense)
        let byKey = Dictionary(uniqueKeysWithValues: fixed.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
    }
}
