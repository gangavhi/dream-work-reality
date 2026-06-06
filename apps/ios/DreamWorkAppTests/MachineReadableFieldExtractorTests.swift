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
        let result = MachineReadableFieldExtractor.extract(from: hints, plainOCRText: "")
        XCTAssertTrue(result.decodedPayload)
        XCTAssertTrue(result.sources.contains("pdf417"))
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.driversLicenseNumber })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.legalLastName })
    }

    func testIndianPassportMRZLinesProduceFields() {
        let mrzLines = [
            "P<INDPATEL<<AMIT<<<<<<<<<<<<<<<<<<<<<<<<<",
            "M1234567<0IND8503150M3001015<<<<<<<<<<<<<<04",
        ]
        let hints = EmbeddedPayloadHints.Result(barcodePayloads: [], mrzLines: mrzLines)
        let result = MachineReadableFieldExtractor.extract(
            from: hints,
            plainOCRText: IndianPassportParserTests.sampleIndianPassportOCRText
        )
        XCTAssertTrue(result.decodedPayload)
        XCTAssertTrue(result.sources.contains("passport"))
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "M1234567")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
    }

    func testPipelineDoesNotUseNameResolverFallback() async {
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
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertFalse(result.usedHeuristicFallback)
        XCTAssertFalse(result.usedMachineReadablePayload)
    }

    func testPipelineExtractsIndianPassportViaOpenVocabularyWhenOnDevice() async {
        let lines = IndianPassportParserTests.sampleIndianPassportOCRText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let blocks = lines.enumerated().map { index, line in
            VisionOcrAdapter.TextBlock(
                text: line,
                confidence: 0.92,
                bounds: VisionOcrAdapter.NormRect(
                    x: 0,
                    y: Float(0.95 - Double(index) * 0.04),
                    width: 0.9,
                    height: 0.035
                )
            )
        }
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [VisionOcrAdapter.Page(blocks: blocks)])

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        XCTAssertFalse(result.suggestions.isEmpty)
        XCTAssertTrue(result.pipelineTrace.contains("extract:semantic"))
        XCTAssertTrue(result.pipelineTrace.contains("mrz:detected:2"))
    }

    func testPipelineExtractsVerticalPassportViaOpenVocabularyWhenOnDevice() async {
        struct Row { let label: String; let value: String; let y: Float }
        let rows: [Row] = [
            Row(label: "REPUBLIC OF INDIA", value: "", y: 0.92),
            Row(label: "Passport No.", value: "M1234567", y: 0.86),
            Row(label: "Surname", value: "PATEL", y: 0.78),
            Row(label: "Given Name(s)", value: "AMIT", y: 0.70),
            Row(label: "Date of Birth", value: "15/03/1985", y: 0.62),
            Row(label: "Place of Birth", value: "MUMBAI, MAHARASHTRA", y: 0.54),
            Row(label: "Date of Expiry", value: "01/01/2030", y: 0.46),
        ]
        var blocks: [VisionOcrAdapter.TextBlock] = []
        for row in rows {
            if !row.label.isEmpty {
                blocks.append(VisionOcrAdapter.TextBlock(
                    text: row.label,
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0.05, y: row.y, width: 0.35, height: 0.03)
                ))
            }
            if !row.value.isEmpty {
                blocks.append(VisionOcrAdapter.TextBlock(
                    text: row.value,
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0.05, y: row.y - 0.035, width: 0.5, height: 0.03)
                ))
            }
        }
        blocks.append(VisionOcrAdapter.TextBlock(
            text: "P<INDPATEL<<AMIT<<<<<<<<<<<<<<<<<<<<<<<<<",
            confidence: 0.88,
            bounds: VisionOcrAdapter.NormRect(x: 0.05, y: 0.12, width: 0.9, height: 0.03)
        ))
        blocks.append(VisionOcrAdapter.TextBlock(
            text: "M1234567<0IND8503150M3001015<<<<<<<<<<<<<<04",
            confidence: 0.88,
            bounds: VisionOcrAdapter.NormRect(x: 0.05, y: 0.08, width: 0.9, height: 0.03)
        ))

        let doc = VisionOcrAdapter.NormalizedDocument(pages: [VisionOcrAdapter.Page(blocks: blocks)])

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)

        XCTAssertFalse(result.suggestions.isEmpty)
        XCTAssertTrue(result.pipelineTrace.contains("extract:semantic"))
        XCTAssertTrue(result.pipelineTrace.contains("mrz:detected:2"))
    }

    func testPipelineExtractsTexasDriverLicenseViaOpenVocabularyWhenOnDevice() async {
        let lines = DriverLicenseParserTests.texasSampleOCRText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let blocks = lines.enumerated().map { index, line in
            VisionOcrAdapter.TextBlock(
                text: line,
                confidence: 0.92,
                bounds: VisionOcrAdapter.NormRect(
                    x: 0,
                    y: Float(0.95 - Double(index) * 0.04),
                    width: 0.9,
                    height: 0.035
                )
            )
        }
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [VisionOcrAdapter.Page(blocks: blocks)])

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)

        XCTAssertFalse(result.suggestions.isEmpty)
        XCTAssertTrue(result.pipelineTrace.contains("extract:semantic"))
        XCTAssertFalse(result.usedHeuristicFallback)
    }
}
