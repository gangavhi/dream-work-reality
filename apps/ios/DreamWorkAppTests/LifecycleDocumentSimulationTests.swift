import XCTest

@testable import DreamWorkApp

/// Simulator tests for major personal & household documents across a typical life cycle.
@MainActor
final class LifecycleDocumentSimulationTests: XCTestCase {
    // MARK: - Deterministic pipeline simulation (synthetic OCR corpus)

    func testAllMajorLifecycleDocumentsExtractFields() async {
        for spec in LifecycleDocumentCatalog.all {
            let document = LifecycleDocumentSimulationHarness.normalizedDocument(from: spec.syntheticOCRLines)
            let result = await LifecycleDocumentSimulationHarness.runPipeline(on: document, label: spec.title)
            XCTAssertGreaterThan(result.suggestions.count, 0, "\(spec.id) should produce suggestions")
            LifecycleDocumentSimulationHarness.assertSpec(spec, result: result)
        }
    }

    func testLifecycleDocumentsByLifeStage() async {
        for stage in LifecycleDocumentCatalog.LifeStage.allCases {
            let specs = LifecycleDocumentCatalog.specs(in: stage)
            XCTAssertFalse(specs.isEmpty, "\(stage.rawValue) needs documents")
            for spec in specs {
                let document = LifecycleDocumentSimulationHarness.normalizedDocument(from: spec.syntheticOCRLines)
                let result = await LifecycleDocumentSimulationHarness.runPipeline(on: document, label: spec.title)
                LifecycleDocumentSimulationHarness.assertSpec(spec, result: result)
            }
        }
    }

    // MARK: - Vision OCR on simulator (photo fixtures + rendered synthetic pages)

    func testVisionOCROnPhotoFixtures() async throws {
        let bundle = Bundle(for: type(of: self))
        let photoSpecs = LifecycleDocumentCatalog.all.filter { $0.bundleImageBaseName != nil }

        for spec in photoSpecs {
            guard let base = spec.bundleImageBaseName,
                  let url = bundle.url(forResource: base, withExtension: "png")
            else {
                throw XCTSkip("Missing fixture \(spec.bundleImageBaseName ?? "").png for \(spec.id)")
            }
            let result = try await runVisionPipeline(url: url, label: spec.title)
            XCTAssertGreaterThan(result.suggestions.count, 0, "\(spec.id) photo OCR")
            // Photo OCR is noisy — verify core identity fields only.
            let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
            XCTAssertFalse(byKey.isEmpty)
            if spec.id == "drivers_license" {
                XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Hiremath")
            }
        }
    }

    func testVisionOCROnRenderedSyntheticDocuments() async throws {
        let renderSpecs = LifecycleDocumentCatalog.all.filter { $0.bundleImageBaseName == nil }

        for spec in renderSpecs {
            let url = try LifecycleDocumentImageRenderer.pngURL(
                from: spec.syntheticOCRLines,
                filename: "lifecycle-vision-\(spec.id).png"
            )
            defer { try? FileManager.default.removeItem(at: url) }

            let result = try await runVisionPipeline(url: url, label: spec.title)
            XCTAssertGreaterThan(result.suggestions.count, 0, "\(spec.id) rendered Vision OCR")
            print("VISION[\(spec.id)] type=\(result.displayType.rawValue) fields=\(result.suggestions.count)")
        }
    }

    @discardableResult
    private func runVisionPipeline(url: URL, label: String) async throws -> DocumentIntelligencePipeline.Result {
        let bridge = RustCoreBridgeService()
        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        XCTAssertGreaterThan(summary.blockCount, 0, "Vision must read \(label)")

        guard let json = bridge.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            XCTFail("Missing normalized JSON for \(label)")
            throw NSError(domain: "LifecycleDocumentSimulationTests", code: 1)
        }

        return await LifecycleDocumentSimulationHarness.runPipeline(on: document, label: label)
    }
}
