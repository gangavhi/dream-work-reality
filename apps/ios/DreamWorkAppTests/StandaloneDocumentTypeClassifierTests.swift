import XCTest
@testable import DreamWorkApp

final class StandaloneDocumentTypeClassifierTests: XCTestCase {
    func testPresentationResolvesMustHaveFeatureListLabels() {
        let cases: [(String, ScannedDocumentType)] = [
            ("driversLicense", .driversLicense),
            ("passport", .passport),
            ("stateId", .stateId),
            ("ssnCard", .ssnCard),
            ("insuranceCard", .insuranceCard),
            ("utilityBill", .utilityBill),
            ("bankStatement", .bankStatement),
            ("w2", .taxDocument),
            ("form1099", .taxDocument),
            ("payStub", .employmentDocument),
        ]
        for (label, expected) in cases {
            let resolved = DocumentTypePresentation.resolve(label)
            XCTAssertEqual(resolved.enumType, expected, "label \(label)")
        }
    }

    func testClassifyIfNeededSkipsHighConfidenceHeuristic() {
        let heuristic = DocumentClassification(
            documentType: .driversLicense,
            confidence: 0.95,
            matchedSignals: ["driver license header"]
        )
        let result = StandaloneDocumentTypeClassifier.classifyIfNeeded(
            ocrText: MustHaveDocumentMockFixtures.driverLicenseOCR,
            heuristic: heuristic
        )
        XCTAssertNil(result, "Create ML should not override confident heuristic")
    }

    func testClassifyIfNeededAcceptsLowConfidenceWhenModelAbsent() {
        let heuristic = DocumentClassification(
            documentType: .other,
            confidence: 0.5,
            matchedSignals: ["no strong signals"]
        )
        let result = StandaloneDocumentTypeClassifier.classifyIfNeeded(
            ocrText: MustHaveDocumentMockFixtures.ssnCardOCR,
            heuristic: heuristic
        )
        // No bundled model in unit tests — nil is expected; heuristic fallbacks still run in pipeline.
        if CreateMLModelRegistry.hasBundledClassifier {
            XCTAssertNotNil(result)
        } else {
            XCTAssertNil(result)
        }
    }
}
