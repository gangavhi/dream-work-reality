import XCTest

@testable import DreamWorkApp

/// E2E: synthetic or local-only passport fixtures → Vision OCR → pipeline.
@MainActor
final class PassportSamplePipelineE2ETests: XCTestCase {
    private func localFixtureURL(resource: String, ext: String) -> URL? {
        let bundle = Bundle(for: type(of: self))
        let diskPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(resource).\(ext)")
        return bundle.url(forResource: resource, withExtension: ext)
            ?? (FileManager.default.fileExists(atPath: diskPath.path) ? diskPath : nil)
    }

    func testUSPassportSampleImageProducesFieldSuggestions() async throws {
        guard let url = localFixtureURL(resource: "sample-document", ext: "png") else {
            throw XCTSkip("Missing DreamWorkAppTests/Fixtures/sample-document.png")
        }

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let bridge = RustCoreBridgeService()
        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        XCTAssertGreaterThan(summary.blockCount, 0, "OCR must detect text on synthetic US passport sample")

        guard let json = bridge.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            XCTFail("Could not load normalized document from Rust peek")
            return
        }

        let result = await DocumentIntelligencePipeline.extract(document: document, fileURL: url)

        print("=== US passport E2E pipeline trace ===")
        print(result.pipelineTrace.joined(separator: " → "))
        print("displayType=\(result.displayType.rawValue) suggestions=\(result.suggestions.count)")

        XCTAssertEqual(result.displayType, .passport)
        XCTAssertGreaterThan(result.suggestions.count, 0, "Synthetic passport sample should yield profile fields")
    }

    /// Optional local PDF for manual QA — never commit real scans; place at Fixtures/indian-passport-reference.pdf (gitignored).
    func testReferenceIndianPassportPDFVisionOCRAndPipeline() async throws {
        guard let url = localFixtureURL(resource: "indian-passport-reference", ext: "pdf") else {
            throw XCTSkip("Missing local-only DreamWorkAppTests/Fixtures/indian-passport-reference.pdf")
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
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })

        print("=== Indian passport E2E (local fixture) ===")
        print("pages=\(summary.pageCount) blocks=\(summary.blockCount)")
        print("displayType=\(result.displayType.rawValue) suggestions=\(result.suggestions.count)")

        XCTAssertEqual(result.displayType, .passport)
        XCTAssertFalse(result.suggestions.isEmpty, "Indian passport PDF should yield fields")

        if let passport = byKey[ProfileFieldKey.passportNumber] {
            XCTAssertTrue(
                passport.range(of: #"^[A-Z]?\d{7,9}$"#, options: .regularExpression) != nil,
                "Passport number should look plausible, got \(passport)"
            )
        }

        let nameKeys: Set<String> = [
            ProfileFieldKey.legalFirstName,
            ProfileFieldKey.legalLastName,
            ProfileFieldKey.displayName,
        ]
        for key in nameKeys {
            if let value = byKey[key] {
                XCTAssertGreaterThanOrEqual(value.count, 2)
                XCTAssertFalse(value.range(of: #"^[a-z]{8,}$"#, options: .regularExpression) != nil && value == value.lowercased())
            }
        }
    }
}
