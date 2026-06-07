import XCTest
@testable import DreamWorkApp

final class OcrTextPostProcessorTests: XCTestCase {
    func testFixesTexassTypo() {
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("Texass"), "TEXAS")
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("* Texass"), "TEXAS")
    }

    func testFixesGarbledDateToken() {
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("з. дov: 03/1511985"), "з. дov: 03/15/1985")
    }

    func testStripsLeadingNoise() {
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("¿ JANE"), "JANE")
    }

    func testCleanFullTextPreservesLineOrder() {
        let input = "SMITH\n¿ JANE\n03/1511985"
        let output = OcrTextPostProcessor.cleanFullText(input)
        XCTAssertTrue(output.contains("SMITH"))
        XCTAssertTrue(output.contains("JANE"))
        XCTAssertTrue(output.contains("03/15/1985"))
    }

    func testFixesNoisyIndianPassportTokens() {
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("26./.12/24.24"), "26/12/2024")
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("02ID6/1990"), "02/06/1990")
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("M49kQ123"), "N4940123")
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("AMITKUMAR.0"), "AMITKUMAR")
        XCTAssertEqual(OcrTextPostProcessor.cleanLine("AMIT.0"), "AMIT")
    }

    func testCollapsesSpacedAddressCaps() {
        let line = "M G R O A D, S H I V A J I N A G A R"
        XCTAssertEqual(OcrTextPostProcessor.cleanLine(line), "MGROAD, SHIVAJINAGAR")
    }
}
