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
        var model_path: String?
        var document_type: String?
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

    /// Plans persistence (table fit + schema + row ops). Rust injects live `sqlite_schema` when omitted.
    static func planStorage(
        fields: [String: String],
        personID: String?,
        profileSchemaKeys: [String],
        documentType: String?
    ) -> StoragePlanSuggestion? {
        let body = PlanStorageRequest(
            fields: fields,
            person_id: personID,
            profile_schema_keys: profileSchemaKeys.isEmpty ? nil : profileSchemaKeys,
            model_path: BundledModelStore.storagePlannerArtifactPath(),
            document_type: documentType
        )
        guard let json = encodeJSON(body),
              let out = callRustJSON(json, dreamwork_plan_storage_json)
        else {
            return nil
        }
        return decodeStoragePlan(out)
    }

    private static func decodeStoragePlan(_ json: String) -> StoragePlanSuggestion? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(StoragePlanWire.self, from: data) else {
            return nil
        }
        let operations = decoded.operations.compactMap { row -> StorageOperationSuggestion? in
            guard let kind = StorageOperationKind(rawValue: row.op) else { return nil }
            return StorageOperationSuggestion(
                kind: kind,
                personID: row.person_id,
                tableName: row.table_name,
                key: row.key,
                value: row.value,
                rowValues: row.row_values ?? [:],
                reason: row.reason
            )
        }
        let schemaActions = (decoded.schema_actions ?? []).map { row in
            SchemaActionSuggestion(
                op: row.op,
                tableName: row.table_name,
                columnName: row.column_name,
                sqlType: row.sql_type,
                nullable: row.nullable ?? true,
                columns: row.columns?.map {
                    SchemaColumnSpec(name: $0.name, sqlType: $0.sql_type, nullable: $0.nullable)
                },
                reason: row.reason
            )
        }
        let target = decoded.storage_target.map {
            StorageTargetDecision(decision: $0.decision, tableName: $0.table_name, reason: $0.reason)
        }
        return StoragePlanSuggestion(
            storageTarget: target,
            schemaActions: schemaActions,
            operations: operations,
            summary: StoragePlanSummary(
                canonicalCount: Int(decoded.summary.canonical_count),
                extensionCount: Int(decoded.summary.extension_count),
                skippedEmpty: Int(decoded.summary.skipped_empty),
                plannerEngine: decoded.summary.planner_engine ?? ModelArtifactSlot.storagePlanner.rawValue,
                plannerStatus: decoded.summary.planner_status ?? "storage_planner_unknown"
            )
        )
    }

    private struct StoragePlanWire: Decodable {
        var storage_target: StorageTargetWire?
        var schema_actions: [SchemaActionWire]?
        var operations: [StorageOperationWire]
        var summary: StoragePlanSummaryWire
    }

    private struct StorageTargetWire: Decodable {
        var decision: String
        var table_name: String
        var reason: String
    }

    private struct SchemaActionWire: Decodable {
        var op: String
        var table_name: String?
        var column_name: String?
        var sql_type: String?
        var nullable: Bool?
        var columns: [SchemaColumnWire]?
        var reason: String
    }

    private struct SchemaColumnWire: Decodable {
        var name: String
        var sql_type: String
        var nullable: Bool
    }

    private struct StorageOperationWire: Decodable {
        var op: String
        var person_id: String?
        var table_name: String?
        var key: String
        var value: String
        var row_values: [String: String]?
        var reason: String
    }

    private struct StoragePlanSummaryWire: Decodable {
        var canonical_count: UInt32
        var extension_count: UInt32
        var skipped_empty: UInt32
        var planner_engine: String?
        var planner_status: String?
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
