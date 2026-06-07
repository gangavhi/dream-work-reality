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

    func testReferenceIndianPassportPDFVisionOCRAndPipeline() async throws {
        let url = URL(fileURLWithPath: "Fixtures/indian-passport-reference.pdf")
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

        print("=== Indian passport E2E (local fixture) ===")
        print("pages=\(summary.pageCount) blocks=\(summary.blockCount)")
        print(result.pipelineTrace.joined(separator: " → "))
        print("displayType=\(result.displayType.rawValue)")
        print("--- OCR reading order ---")
        print(layoutText)
        print("--- mapped fields ---")
        for s in result.suggestions {
            print("  \(s.profileKey)=\(s.value) conf=\(s.confidence)")
        }

        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(result.displayType, .passport)
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jordan")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Lee"
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "P1234567")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "05/06/1995")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "22/01/2027")
        XCTAssertNotNil(byKey[ProfileFieldKey.passportAddress])
    }
}
