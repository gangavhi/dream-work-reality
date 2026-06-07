import XCTest

@testable import DreamWorkApp

@MainActor
final class InsuranceCardPipelineE2ETests: XCTestCase {
    private func localFixtureURL(resource: String, ext: String) -> URL? {
        let diskPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(resource).\(ext)")
        return FileManager.default.fileExists(atPath: diskPath.path) ? diskPath : nil
    }

    /// Optional local PDF for manual QA — never commit real cards; place at Fixtures/insurance-cards-reference.pdf (gitignored).
    func testInsuranceCardsPDFVisionOCRAndPipeline() async throws {
        guard let url = localFixtureURL(resource: "insurance-cards-reference", ext: "pdf") else {
            throw XCTSkip("Missing local-only DreamWorkAppTests/Fixtures/insurance-cards-reference.pdf")
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

        let result = await DocumentIntelligencePipeline.extract(document: document, fileURL: url)

        print("=== Insurance cards E2E (local fixture) ===")
        print("pages=\(summary.pageCount) blocks=\(summary.blockCount)")
        print("displayType=\(result.displayType.rawValue) suggestions=\(result.suggestions.count)")

        XCTAssertEqual(result.displayType, .insuranceCard)
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertFalse(result.suggestions.isEmpty, "Insurance PDF should yield fields")
        XCTAssertTrue(
            byKey[ProfileFieldKey.insuranceMemberId] != nil
                || byKey[ProfileFieldKey.insuranceCarrier] != nil
                || byKey[ProfileFieldKey.legalFirstName] != nil,
            "Expected member id, carrier, or holder name"
        )
    }
}
