import XCTest
@testable import DreamWorkApp

final class MachineReadableFieldExtractorTests: XCTestCase {
    func testPDF417PayloadProducesDriversLicenseFields() {
        let payload = """
        ANSI636000010002DL00410288
        DCSMARTIN
        DACJANE
        DAQ12345678
        DBB19900425
        DAG2457 MEADOWBROOK AVE
        DAIAUSTIN
        DAJTX
        DAK787010000
        """
        let hints = EmbeddedPayloadHints.Result(
            barcodePayloads: [payload],
            mrzLines: []
        )
        let result = MachineReadableFieldExtractor.extract(from: hints, supplementalOCRText: "")
        XCTAssertTrue(result.decodedPayload)
        XCTAssertTrue(result.sources.contains("pdf417"))
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.driversLicenseNumber })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.legalLastName })
    }

    func testPipelineSkipsPersonNameResolverTexasOverride() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                VisionOcrAdapter.TextBlock(
                    text: "Jane Utility Company",
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0, y: 0.5, width: 0.8, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "DRIVER LICENSE",
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0, y: 0.4, width: 0.5, height: 0.05)
                ),
            ]),
        ])

        let previous = GenAISettings.provider
        GenAISettings.provider = .off
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        let display = result.suggestions.first { $0.profileKey == ProfileFieldKey.displayName }?.value
        XCTAssertEqual(display, "Jane Utility Company")
    }
}
