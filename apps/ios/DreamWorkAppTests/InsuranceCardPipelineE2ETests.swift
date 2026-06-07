import XCTest

@testable import DreamWorkApp

@MainActor
final class InsuranceCardPipelineE2ETests: XCTestCase {
    func testUHCInsuranceCardsPDFVisionOCRAndPipeline() async throws {
        let url = URL(fileURLWithPath: "Fixtures/insurance-cards-reference.pdf")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference PDF at \(url.path)")
        }

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let bridge = RustCoreBridgeService()
        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        XCTAssertGreaterThan(summary.blockCount, 0)

        guard let json = bridge.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            XCTFail("Could not load normalized document from Rust peek")
            return
        }

        let layoutText = OcrLayoutSerializer.serialize(document: document)
        let result = await DocumentIntelligencePipeline.extract(document: document, fileURL: url)

        print("=== UHC insurance cards E2E ===")
        print("pages=\(summary.pageCount) blocks=\(summary.blockCount)")
        print(result.pipelineTrace.joined(separator: " → "))
        print("displayType=\(result.displayType.rawValue)")
        try? layoutText.write(toFile: "/tmp/uhc_insurance_ocr.txt", atomically: true, encoding: .utf8)
        print("--- OCR reading order (first 80 lines) ---")
        print(layoutText.components(separatedBy: .newlines).prefix(80).joined(separator: "\n"))
        print("--- mapped fields ---")
        for s in result.suggestions {
            print("  \(s.profileKey)=\(s.value) conf=\(s.confidence)")
        }

        XCTAssertEqual(result.displayType, .insuranceCard)
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertFalse(result.suggestions.isEmpty, "UHC PDF should yield insurance fields")
        XCTAssertTrue(
            byKey[ProfileFieldKey.insuranceMemberId] != nil
                || byKey[ProfileFieldKey.insuranceCarrier] != nil
                || byKey[ProfileFieldKey.legalFirstName] != nil,
            "Expected member id, carrier, or holder name from portal header"
        )
    }
}
