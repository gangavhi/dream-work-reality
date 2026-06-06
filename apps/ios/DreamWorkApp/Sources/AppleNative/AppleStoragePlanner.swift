import Foundation

/// Deterministic SQLite storage plan from extracted fields (no LLM / Rust storage planner).
enum AppleStoragePlanner {
    static func plan(
        fields: [String: String],
        personID: String?,
        profileSchemaKeys: [String],
        documentType: String? = nil
    ) -> StoragePlanSuggestion {
        _ = documentType
        let canonical = Set(profileSchemaKeys)
        var operations: [StorageOperationSuggestion] = []
        var canonicalCount = 0
        var extensionCount = 0
        var skippedEmpty = 0

        for (key, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                skippedEmpty += 1
                continue
            }
            if canonical.contains(key) {
                operations.append(StorageOperationSuggestion(
                    kind: .upsertManualField,
                    personID: personID,
                    tableName: nil,
                    key: key,
                    value: trimmed,
                    reason: "apple_native:canonical_profile_field"
                ))
                canonicalCount += 1
            } else {
                operations.append(StorageOperationSuggestion(
                    kind: .upsertExtensionField,
                    personID: personID,
                    tableName: nil,
                    key: key,
                    value: trimmed,
                    reason: "apple_native:extension_field"
                ))
                extensionCount += 1
            }
        }

        return StoragePlanSuggestion(
            storageTarget: StorageTargetDecision(
                decision: "use_manual_entry",
                tableName: "manual_entry",
                reason: "apple_native:profile_fields_only"
            ),
            schemaActions: [],
            operations: operations,
            summary: StoragePlanSummary(
                canonicalCount: canonicalCount,
                extensionCount: extensionCount,
                skippedEmpty: skippedEmpty,
                plannerEngine: "apple_native",
                plannerStatus: "storage_planner_active"
            )
        )
    }
}
