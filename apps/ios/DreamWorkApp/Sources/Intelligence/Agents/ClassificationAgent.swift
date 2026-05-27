import Foundation

/// Document type classification via local GGUF inference only. Missing/failed model states are
/// returned explicitly so the review UI can surface them; there is no keyword or payload fallback.
enum ClassificationAgent {
    struct Result: Hashable {
        let openDocumentType: String?
        let displayLabel: String
        let enumType: ScannedDocumentType
        let confidence: Double
        let engineID: String
        let issuerRegion: String?
        let country: String?
        let runtimeStatus: String
    }

    private struct ClassifyRequest: Encodable {
        var layout_text: String
        var model_path: String?
    }

    private struct ClassifyResponse: Decodable {
        var document_type: String
        var display_label: String
        var confidence: Double
        var engine: String
        var status: String
    }

    /// Placeholder until the single on-device parser pass returns `document_type`.
    static func pendingParserClassification() -> Result {
        Result(
            openDocumentType: nil,
            displayLabel: "Document",
            enumType: .other,
            confidence: 0,
            engineID: ModelArtifactSlot.generativeLLM.rawValue,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: "classifier_pending_parser"
        )
    }

    static func classify(
        modelInput: String,
        mappedDocumentType: String?,
        machineReadableSources: [String]
    ) -> Result {
        _ = mappedDocumentType
        _ = machineReadableSources

        let trimmed = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return failed(status: "classifier_input_empty")
        }

        guard GenAISettings.provider == .onDevice else {
            return failed(status: "classifier_skipped:provider_off")
        }

        let body = ClassifyRequest(
            layout_text: String(trimmed.prefix(24_000)),
            model_path: BundledModelStore.documentClassifierArtifactPath()
        )
        guard let json = encodeJSON(body),
              let out = callRustJSON(json, dreamwork_classify_document_json),
              let decoded = try? JSONDecoder().decode(ClassifyResponse.self, from: Data(out.utf8))
        else {
            return failed(status: "classifier_bridge_failed")
        }

        guard decoded.status == "classifier_active",
              decoded.document_type != "unknown",
              decoded.confidence > 0
        else {
            return failed(status: decoded.status, engineID: decoded.engine)
        }

        let presentation = DocumentTypePresentation.resolve(decoded.document_type)
        return Result(
            openDocumentType: decoded.document_type,
            displayLabel: decoded.display_label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? presentation.displayLabel
                : decoded.display_label,
            enumType: presentation.enumType,
            confidence: decoded.confidence,
            engineID: decoded.engine,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: decoded.status
        )
    }

    private static func failed(status: String, engineID: String = ModelArtifactSlot.documentClassifier.rawValue) -> Result {
        Result(
            openDocumentType: nil,
            displayLabel: "Document classifier failed",
            enumType: .other,
            confidence: 0,
            engineID: engineID,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: status
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func callRustJSON(
        _ json: String,
        _ fn: (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    ) -> String? {
        json.withCString { ptr in
            guard let raw = fn(ptr) else { return nil }
            defer { dreamwork_string_free(raw) }
            return String(cString: raw)
        }
    }
}

@_silgen_name("dreamwork_classify_document_json")
private func dreamwork_classify_document_json(_ jsonUtf8: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_string_free")
private func dreamwork_string_free(_ pointer: UnsafeMutablePointer<CChar>?)
