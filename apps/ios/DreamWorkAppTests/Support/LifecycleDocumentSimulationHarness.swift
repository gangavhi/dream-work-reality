import Foundation
import XCTest
@testable import DreamWorkApp

enum LifecycleDocumentSimulationHarness {
    /// Builds a normalized OCR document from synthetic lines (deterministic simulator pipeline input).
    static func normalizedDocument(from lines: [String]) -> VisionOcrAdapter.NormalizedDocument {
        let blocks = lines.enumerated().map { index, line in
            VisionOcrAdapter.TextBlock(
                text: line,
                confidence: 0.96,
                bounds: VisionOcrAdapter.NormRect(
                    x: 0.05,
                    y: Float(max(0.02, 0.94 - Double(index) * 0.055)),
                    width: 0.9,
                    height: 0.05
                )
            )
        }
        return VisionOcrAdapter.NormalizedDocument(pages: [VisionOcrAdapter.Page(blocks: blocks)])
    }

    static func runPipeline(
        on document: VisionOcrAdapter.NormalizedDocument,
        label: String
    ) async -> DocumentIntelligencePipeline.Result {
        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }
        return await DocumentIntelligencePipeline.extract(document: document)
    }

    static func assertSpec(
        _ spec: LifecycleDocumentCatalog.Spec,
        result: DocumentIntelligencePipeline.Result,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if spec.expectedType != .other {
            XCTAssertEqual(
                result.displayType,
                spec.expectedType,
                "\(spec.id): document type",
                file: file,
                line: line
            )
        }

        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })
        for key in spec.requiredProfileKeys {
            XCTAssertNotNil(byKey[key], "\(spec.id): missing \(key)", file: file, line: line)
        }
        for (key, check) in spec.fieldChecks {
            guard let value = byKey[key] else { continue }
            XCTAssertTrue(check(value), "\(spec.id): bad \(key)=\(value)", file: file, line: line)
        }
    }

    static func debugSummary(for spec: LifecycleDocumentCatalog.Spec) async -> String {
        let document = normalizedDocument(from: spec.syntheticOCRLines)
        let result = await runPipeline(on: document, label: spec.title)
        let fields = result.suggestions.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | ")
        return "[\(spec.id)] type=\(result.displayType.rawValue) count=\(result.suggestions.count) \(fields)"
    }
}
