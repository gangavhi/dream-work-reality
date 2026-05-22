import XCTest
@testable import DreamWorkApp

final class DocumentTypePresentationTests: XCTestCase {
    func testMapsKnownOpenVocabulary() {
        let result = DocumentTypePresentation.resolve("drivers_license")
        XCTAssertEqual(result.enumType, .driversLicense)
    }

    func testUnknownTypeStaysOtherWithHumanLabel() {
        let result = DocumentTypePresentation.resolve("hoa_assessment_notice")
        XCTAssertEqual(result.enumType, .other)
        XCTAssertEqual(result.displayLabel, "Hoa Assessment Notice")
    }
}
