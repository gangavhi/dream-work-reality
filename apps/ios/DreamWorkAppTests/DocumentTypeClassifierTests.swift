import XCTest
@testable import DreamWorkApp

final class DocumentTypeClassifierTests: XCTestCase {
    func testTexasDriverLicenseHeaderIsFullConfidence() {
        let text = DriverLicenseParserTests.texasSampleOCRText
        let result = DocumentTypeClassifier.classify(from: text)
        XCTAssertEqual(result.documentType, .driversLicense)
        XCTAssertEqual(result.confidence, 1.0)
    }

    func testNoisyTexasOCRRefinesToFullConfidenceWithStructuredScan() {
        let text = DriverLicenseParserTests.texasSampleNoisyOCRText
        let base = DocumentTypeClassifier.classify(from: text)
        XCTAssertEqual(base.documentType, .driversLicense)
        XCTAssertGreaterThanOrEqual(base.confidence, 0.92)

        let parsed = DriverLicenseParser.parse(text)
        let refined = DocumentTypeClassifier.refine(
            base,
            driverLicenseScan: parsed,
            fullText: text
        )
        XCTAssertEqual(refined.confidence, 1.0)
        XCTAssertTrue(refined.matchedSignals.contains("structured ID extraction"))
    }

    func testTexasParserAloneRefinesToFullConfidence() {
        let text = DriverLicenseParserTests.texasSampleNoisyOCRText
        let base = DocumentTypeClassifier.classify(from: text)
        let refined = DocumentTypeClassifier.refine(base, driverLicenseScan: nil, fullText: text)
        XCTAssertEqual(refined.confidence, 1.0)
        XCTAssertTrue(refined.matchedSignals.contains("Texas DL field layout"))
    }

    func testSocialSecurityCardDetection() {
        let text = """
        SOCIAL SECURITY ADMINISTRATION
        Jane Smith
        123-45-6789
        """
        let result = DocumentTypeClassifier.classify(from: text)
        XCTAssertEqual(result.documentType, .ssnCard)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.88)
    }
}
