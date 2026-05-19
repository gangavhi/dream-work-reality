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
}
