import Foundation

/// Zero-egress document field extraction via embedded Rust core (no HTTP).
enum OnDeviceFieldMapper {
    private struct MapRequest: Encodable {
        var layout_text: String
        var profile_schema_keys: [String]
        var model_path: String?
    }

    private struct FieldDTO: Decodable {
        var value: String
        var label: String?
    }

    private struct MapResponse: Decodable {
        var document_type: String
        var issuer_region: String?
        var country: String?
        var fields: [String: FieldDTO]
        var engine: String
        var model_artifact_id: String
        var gguf_present: Bool
        var gguf_valid: Bool
    }

    /// Maps layout OCR text using the Rust on-device engine (heuristics + optional GGUF validation).
    static func mapFields(
        layoutText: String,
        profileSchemaKeys: [String]
    ) -> (suggestions: [OcrFieldSuggestion], documentType: String?, usedOnDevice: Bool)? {
        let trimmed = layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let body = MapRequest(
            layout_text: String(trimmed.prefix(24_000)),
            profile_schema_keys: profileSchemaKeys,
            model_path: BundledModelStore.liteArtifactPath()
        )
        guard let json = encodeJSON(body),
              let out = callRustJSON(json, dreamwork_map_document_fields_json),
              let decoded = try? JSONDecoder().decode(MapResponse.self, from: Data(out.utf8)),
              !decoded.fields.isEmpty
        else {
            return nil
        }

        let presentation = DocumentTypePresentation.resolve(decoded.document_type)
        var extraction = GenAIFieldMapper.ExtractionResult(
            values: [:],
            labels: [:],
            documentType: decoded.document_type,
            issuerRegion: decoded.issuer_region,
            country: decoded.country
        )
        for (rawKey, field) in decoded.fields {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            extraction.values[key] = value
            if let label = field.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                extraction.labels[key] = label
            }
        }
        guard !extraction.values.isEmpty else { return nil }

        let suggestions = GenAIFieldMapper.suggestions(
            from: extraction,
            documentType: presentation.enumType
        ).map { $0.withMappingSource(.onDevice) }
        return (suggestions, decoded.document_type, true)
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

@_silgen_name("dreamwork_map_document_fields_json")
private func dreamwork_map_document_fields_json(_ jsonUtf8: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_string_free")
private func dreamwork_string_free(_ pointer: UnsafeMutablePointer<CChar>?)
