import XCTest

@testable import DreamWorkApp

/// E2E: real passport sample image → Vision OCR → DocumentIntelligencePipeline (investigation harness).
@MainActor
final class PassportSamplePipelineE2ETests: XCTestCase {
    func testUSPassportSampleImageProducesFieldSuggestions() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "sample-document", withExtension: "png") else {
            throw XCTSkip("Missing DreamWorkAppTests/Fixtures/sample-document.png")
        }

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let bridge = RustCoreBridgeService()
        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        XCTAssertGreaterThan(summary.blockCount, 0, "OCR must detect text on us-passport-sample.png")

        guard let json = bridge.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            XCTFail("Could not load normalized document from Rust peek")
            return
        }

        let result = await DocumentIntelligencePipeline.extract(document: document, fileURL: url)

        print("=== Passport E2E pipeline trace ===")
        print(result.pipelineTrace.joined(separator: " → "))
        print("displayType=\(result.displayType.rawValue) openLabel=\(result.openDocumentTypeLabel)")
        print("usedAI=\(result.usedAI) heuristicFallback=\(result.usedHeuristicFallback) machineReadable=\(result.usedMachineReadablePayload)")
        print("suggestionCount=\(result.suggestions.count)")
        for s in result.suggestions {
            print("  \(s.profileKey)=\(s.value) conf=\(s.confidence) src=\(s.mappingSource?.rawValue ?? "nil")")
        }

        XCTAssertGreaterThan(
            result.suggestions.count,
            0,
            "Passport sample should yield at least one profile field suggestion"
        )
    }
}
