import UIKit
import XCTest

@testable import DreamWorkApp

/// Reproduces document upload → scan review under Apple-native extraction on the simulator.
@MainActor
final class DocumentImportCrashSimulationTests: XCTestCase {
    private var previousGenAI: GenAISettings.Provider!

    override func setUp() {
        super.setUp()
        previousGenAI = GenAISettings.provider
        GenAISettings.provider = .appleNative
    }

    override func tearDown() {
        GenAISettings.provider = previousGenAI
        OnDeviceMemoryGuard.testForceLowMemory = false
        OnDeviceMemoryGuard.testTreatSimulatorLikeDevice = false
        OnDeviceMLPolicy.testSimulatePhysicalIPhone = false
        super.tearDown()
    }

    func testPostUploadPipelineTimelineLogsMemoryAtEachPhase() async throws {
        let bridge = RustCoreBridgeService()
        let url = try writeSyntheticDriverLicenseImage()
        defer { try? FileManager.default.removeItem(at: url) }

        var timeline: [String] = []
        timeline.append(phase("0_import_start", OnDeviceMemoryGuard.snapshot()))

        let runsBefore = bridge.extractionRunCount()
        let ocrSummary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        timeline.append(phase("1_after_ocr_and_sqlite", OnDeviceMemoryGuard.snapshot()))
        timeline.append(
            "ocr_pages=\(ocrSummary.pageCount) blocks=\(ocrSummary.blockCount)"
        )

        let enrichment = await bridge.enrichScanReview(
            document: ocrSummary.document,
            runOnDeviceLLM: true
        )
        timeline.append(phase("2_after_apple_native_enrichment", OnDeviceMemoryGuard.snapshot()))
        timeline.append("trace=\(enrichment.pipelineTrace.joined(separator: " | "))")
        timeline.append("suggestions=\(enrichment.suggestions.count) stack=apple_native")

        let runsAfter = bridge.extractionRunCount()
        XCTAssertEqual(runsAfter, runsBefore + 1)
        XCTAssertTrue(enrichment.pipelineTrace.contains { $0.contains("apple_native") })

        let report = timeline.joined(separator: "\n")
        print("\n--- DOCUMENT IMPORT PIPELINE TIMELINE ---\n\(report)\n--- END TIMELINE ---\n")
        XCTAssertFalse(report.isEmpty)
    }

    func testAutomaticExtractionEnabledByDefault() async throws {
        OnDeviceMLPolicy.testSimulatePhysicalIPhone = false
        XCTAssertTrue(OnDeviceMLPolicy.allowsAutomaticInferenceOnScan)

        let bridge = RustCoreBridgeService()
        let doc = syntheticNormalizedDocument()
        let preview = await bridge.enrichScanReview(document: doc, runOnDeviceLLM: true)
        XCTAssertTrue(preview.pipelineTrace.contains { $0.contains("stack:apple_native") })
    }

    func testMemoryPressureGuardStillQueryable() async throws {
        OnDeviceMemoryGuard.testTreatSimulatorLikeDevice = true
        OnDeviceMemoryGuard.testForceLowMemory = true
        defer { OnDeviceMemoryGuard.testForceLowMemory = false }

        XCTAssertFalse(OnDeviceMemoryGuard.mayRunHeavyInference())

        let bridge = RustCoreBridgeService()
        let doc = syntheticNormalizedDocument()
        let result = await bridge.enrichScanReview(document: doc, runOnDeviceLLM: true)
        XCTAssertFalse(result.suggestions.isEmpty)
    }

    // MARK: - Helpers

    private func phase(_ name: String, _ snapshot: OnDeviceMemoryGuard.Snapshot) -> String {
        "\(name): \(snapshot.logLine) heavy_allowed=\(OnDeviceMemoryGuard.mayRunHeavyInference())"
    }

    private func syntheticNormalizedDocument() -> VisionOcrAdapter.NormalizedDocument {
        VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                VisionOcrAdapter.TextBlock(
                    text: "TEXAS DRIVER LICENSE",
                    confidence: 0.96,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.9, width: 0.6, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "First Name: Jane",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.8, width: 0.4, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "DOB: 03/15/1985",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.6, width: 0.4, height: 0.05)
                ),
            ]),
        ])
    }

    private func writeSyntheticDriverLicenseImage() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 760))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 760))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            let lines = [
                "TEXAS DRIVER LICENSE",
                "First Name: Jane",
                "Last Name: Smith",
                "DOB: 03/15/1985",
                "License No: D12345678",
            ]
            var y: CGFloat = 40
            for line in lines {
                line.draw(at: CGPoint(x: 40, y: y), withAttributes: attrs)
                y += 52
            }
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-dl-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
