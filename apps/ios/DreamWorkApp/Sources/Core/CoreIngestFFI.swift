import Foundation

/// Stage 2 + Stage 3 via Rust FFI (no port-forward).
enum CoreIngestFFI {
    private struct ResolveRequest: Encodable {
        var fields: [String: String]
        var existing_persons: [ExistingPersonDTO]?
    }

    private struct ExistingPersonDTO: Encodable {
        var person_id: String
        var fields: [String: String]
    }

    private struct ResolveResponse: Decodable {
        var resolution: String
        var person_id: String?
        var confidence: Double
        var candidates: [ResolveCandidateDTO]?
    }

    private struct ResolveCandidateDTO: Decodable {
        var person_id: String
        var score: Double
        var reasons: [String]?
        var reason: String?
    }

    private struct PlanStorageRequest: Encodable {
        var fields: [String: String]
        var person_id: String?
        var profile_schema_keys: [String]?
    }

    private struct PlanStorageResponse: Decodable {
        var operations: [StorageOperationDTO]
        var summary: StoragePlanSummaryDTO
    }

    private struct StorageOperationDTO: Decodable {
        var op: String
        var person_id: String?
        var key: String
        var value: String
        var reason: String
    }

    private struct StoragePlanSummaryDTO: Decodable {
        var canonical_count: UInt32
        var extension_count: UInt32
        var skipped_empty: UInt32
    }

    static func resolvePerson(
        fields: [String: String],
        people: [PersonRecord]
    ) -> PersonResolutionSuggestion? {
        let existing = people.map { person in
            ExistingPersonDTO(
                person_id: person.id,
                fields: Dictionary(uniqueKeysWithValues: person.fields.map { ($0.key, $0.value) })
            )
        }
        let body = ResolveRequest(
            fields: fields,
            existing_persons: existing.isEmpty ? nil : existing
        )
        guard let json = encodeJSON(body),
              let out = callRustJSON(json, dreamwork_resolve_person_json)
        else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(ResolveResponse.self, from: Data(out.utf8)) else {
            return nil
        }
        let resolution = PersonResolutionKind(rawValue: decoded.resolution) ?? .ambiguous
        let candidates = (decoded.candidates ?? []).map { row in
            let reasons = row.reasons ?? (row.reason.map { [$0] } ?? [])
            return PersonResolutionCandidate(
                personID: row.person_id,
                score: row.score,
                reasons: reasons
            )
        }
        return PersonResolutionSuggestion(
            resolution: resolution,
            personID: decoded.person_id,
            confidence: decoded.confidence,
            candidates: candidates
        )
    }

    static func planStorage(
        fields: [String: String],
        personID: String?,
        profileSchemaKeys: [String]
    ) -> StoragePlanSuggestion? {
        let body = PlanStorageRequest(
            fields: fields,
            person_id: personID,
            profile_schema_keys: profileSchemaKeys.isEmpty ? nil : profileSchemaKeys
        )
        guard let json = encodeJSON(body),
              let out = callRustJSON(json, dreamwork_plan_storage_json)
        else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(PlanStorageResponse.self, from: Data(out.utf8)) else {
            return nil
        }
        let operations = decoded.operations.compactMap { row -> StorageOperationSuggestion? in
            guard let kind = StorageOperationKind(rawValue: row.op) else { return nil }
            return StorageOperationSuggestion(
                kind: kind,
                personID: row.person_id,
                key: row.key,
                value: row.value,
                reason: row.reason
            )
        }
        return StoragePlanSuggestion(
            operations: operations,
            summary: StoragePlanSummary(
                canonicalCount: Int(decoded.summary.canonical_count),
                extensionCount: Int(decoded.summary.extension_count),
                skippedEmpty: Int(decoded.summary.skipped_empty)
            )
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

@_silgen_name("dreamwork_resolve_person_json")
private func dreamwork_resolve_person_json(_ jsonUtf8: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_plan_storage_json")
private func dreamwork_plan_storage_json(_ jsonUtf8: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_string_free")
private func dreamwork_string_free(_ pointer: UnsafeMutablePointer<CChar>?)
