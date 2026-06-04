import Foundation

enum StorageOperationKind: String, Codable, Hashable {
    case upsertManualField = "upsert_manual_field"
    case upsertExtensionField = "upsert_extension_field"
    case insertRow = "insert_row"
    case createTable = "create_table"
    case addColumn = "add_column"
}

struct StorageTargetDecision: Hashable, Codable {
    let decision: String
    let tableName: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case decision
        case tableName = "table_name"
        case reason
    }
}

struct SchemaColumnSpec: Hashable, Codable {
    let name: String
    let sqlType: String
    let nullable: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case sqlType = "sql_type"
        case nullable
    }
}

struct SchemaActionSuggestion: Identifiable, Hashable, Codable {
    let op: String
    let tableName: String?
    let columnName: String?
    let sqlType: String?
    let nullable: Bool
    let columns: [SchemaColumnSpec]?
    let reason: String

    var id: String { "\(op)-\(tableName ?? "")-\(columnName ?? "")" }

    enum CodingKeys: String, CodingKey {
        case op
        case tableName = "table_name"
        case columnName = "column_name"
        case sqlType = "sql_type"
        case nullable
        case columns
        case reason
    }
}

struct StorageOperationSuggestion: Identifiable, Hashable, Codable {
    let kind: StorageOperationKind
    let personID: String?
    let tableName: String?
    let key: String
    let value: String
    let rowValues: [String: String]
    let reason: String

    var id: String { "\(kind.rawValue)-\(tableName ?? personID ?? "")-\(key)" }

    var targetLabel: String {
        switch kind {
        case .upsertManualField: return "Profile field"
        case .upsertExtensionField: return "Extension field"
        case .insertRow: return "Table row (\(tableName ?? "table"))"
        case .createTable, .addColumn: return "Schema"
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind = "op"
        case personID = "person_id"
        case tableName = "table_name"
        case key
        case value
        case rowValues = "row_values"
        case reason
    }

    init(
        kind: StorageOperationKind,
        personID: String?,
        tableName: String?,
        key: String,
        value: String,
        rowValues: [String: String] = [:],
        reason: String
    ) {
        self.kind = kind
        self.personID = personID
        self.tableName = tableName
        self.key = key
        self.value = value
        self.rowValues = rowValues
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .kind)
        kind = StorageOperationKind(rawValue: op) ?? .upsertExtensionField
        personID = try c.decodeIfPresent(String.self, forKey: .personID)
        tableName = try c.decodeIfPresent(String.self, forKey: .tableName)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        rowValues = try c.decodeIfPresent([String: String].self, forKey: .rowValues) ?? [:]
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encodeIfPresent(personID, forKey: .personID)
        try c.encodeIfPresent(tableName, forKey: .tableName)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value)
        if !rowValues.isEmpty { try c.encode(rowValues, forKey: .rowValues) }
        try c.encode(reason, forKey: .reason)
    }
}

struct StoragePlanSummary: Hashable, Codable {
    let canonicalCount: Int
    let extensionCount: Int
    let skippedEmpty: Int
    let plannerEngine: String
    let plannerStatus: String

    enum CodingKeys: String, CodingKey {
        case canonicalCount = "canonical_count"
        case extensionCount = "extension_count"
        case skippedEmpty = "skipped_empty"
        case plannerEngine = "planner_engine"
        case plannerStatus = "planner_status"
    }
}

struct StoragePlanApplyResult: Hashable, Codable {
    let applied: Bool
    let status: String
    let ddlApplied: Int
    let rowsWritten: Int
    let profileFieldsWritten: Int

    enum CodingKeys: String, CodingKey {
        case applied
        case status
        case ddlApplied = "ddl_applied"
        case rowsWritten = "rows_written"
        case profileFieldsWritten = "profile_fields_written"
    }
}

struct StoragePlanSuggestion: Hashable, Codable {
    let storageTarget: StorageTargetDecision?
    let schemaActions: [SchemaActionSuggestion]
    let operations: [StorageOperationSuggestion]
    let summary: StoragePlanSummary
    let applyResult: StoragePlanApplyResult?

    enum CodingKeys: String, CodingKey {
        case storageTarget = "storage_target"
        case schemaActions = "schema_actions"
        case operations
        case summary
        case applyResult = "apply_result"
    }

    init(
        storageTarget: StorageTargetDecision?,
        schemaActions: [SchemaActionSuggestion],
        operations: [StorageOperationSuggestion],
        summary: StoragePlanSummary,
        applyResult: StoragePlanApplyResult? = nil
    ) {
        self.storageTarget = storageTarget
        self.schemaActions = schemaActions
        self.operations = operations
        self.summary = summary
        self.applyResult = applyResult
    }
}
