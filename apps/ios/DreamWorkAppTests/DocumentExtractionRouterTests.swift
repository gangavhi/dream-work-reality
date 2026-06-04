import XCTest
@testable import DreamWorkApp

final class DocumentExtractionRouterTests: XCTestCase {
    func testMRZRoutesToKnownFastPath() {
        let hints = EmbeddedPayloadHints.Result(
            barcodePayloads: [],
            mrzLines: ["P<USASMITH<<JOHN<<<<<<<<<<<<<<<<<<<<<<<<<<<"]
        )
        let decision = DocumentExtractionRouter.decide(
            classification: ClassificationAgent.pendingParserClassification(),
            payloadHints: hints,
            layout: emptyLayout
        )
        XCTAssertEqual(decision.route, .knownFastPath)
        XCTAssertTrue(decision.signals.contains("signal:mrz"))
    }

    func testUnknownProseRoutesToSemanticPath() {
        let layout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "Dear Sir, please find attached my letter.",
            modelInput: "Dear Sir, please find attached my letter.",
            blocks: [],
            labelValuePairs: [],
            engineID: "test"
        )
        let decision = DocumentExtractionRouter.decide(
            classification: ClassificationAgent.pendingParserClassification(),
            payloadHints: .empty,
            layout: layout
        )
        XCTAssertEqual(decision.route, .unknownSemantic)
    }

    func testDriversLicenseKeywordRoutesKnownFast() {
        let layout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "TEXAS DRIVER LICENSE\n1. Name\nSMITH",
            modelInput: "TEXAS DRIVER LICENSE",
            blocks: [],
            labelValuePairs: [OcrLayoutSerializer.LabelValuePair(label: "Name", value: "SMITH")],
            engineID: "test"
        )
        let decision = DocumentExtractionRouter.decide(
            classification: ClassificationAgent.pendingParserClassification(),
            payloadHints: .empty,
            layout: layout
        )
        XCTAssertEqual(decision.route, .knownFastPath)
    }

    func testValidationRejectsExpirationBeforeIssue() {
        let suggestions = [
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.driversLicenseIssueDate,
                label: "Issue",
                value: "2024-06-01",
                confidence: "High",
                confidenceScore: 0.9,
                mappingSource: .barcode
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.driversLicenseExpiry,
                label: "Expiry",
                value: "2020-01-01",
                confidence: "High",
                confidenceScore: 0.9,
                mappingSource: .barcode
            ),
        ]
        let report = DocumentValidationPipeline.validate(
            suggestions,
            documentType: .driversLicense,
            ocrCorpus: "2024-06-01 2020-01-01"
        )
        XCTAssertFalse(report.suggestions.contains { $0.profileKey == ProfileFieldKey.driversLicenseExpiry })
        XCTAssertTrue(report.warnings.contains("expiration_before_issue"))
    }

    private var emptyLayout: LayoutIntelligenceAgent.LayoutDocument {
        LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "",
            modelInput: "",
            blocks: [],
            labelValuePairs: [],
            engineID: "test"
        )
    }
}
