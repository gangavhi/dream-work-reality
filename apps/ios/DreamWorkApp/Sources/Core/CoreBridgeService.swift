import Foundation

protocol CoreBridgeService {
    func fetchStatus() -> String
    func saveManualEntry(id: String, displayName: String) -> Bool
    func savePerson(_ person: PersonRecord) -> Bool
    func deletePerson(id: String) -> Bool
    func readManualEntryName(id: String) -> String?
    func manualEntryCount() -> Int
    func listPeople() -> [PersonRecord]
    /// Persist normalized OCR JSON (`NormalizedDocument`) — appends `extraction_run` in SQLite.
    func ingestNormalizedDocumentJSON(_ json: String) -> Bool
    func extractionRunCount() -> Int
    func peekLastNormalizedDocumentJSON() -> String?
}

extension CoreBridgeService {
    /// General-purpose ingest: layout OCR → on-device LLM (when enabled) → validators → Rust FFI.
    func enrichScanReview(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> ScanReviewEnrichment {
        let people = listPeople()
        let schemaKeys = ProfileSchema.allFields.map(\.key)
        let extracted = await DocumentIntelligencePipeline.extract(document: document, fileURL: fileURL)

        let fieldMap = CoreIngestHTTPClient.fieldMap(from: extracted.suggestions)
        let personResolution = CoreIngestFFI.resolvePerson(fields: fieldMap, people: people)

        let planPersonID: String? = {
            guard let resolution = personResolution,
                  resolution.resolution == .matchExisting,
                  let id = resolution.personID
            else { return nil }
            return id
        }()
        let storagePlan = CoreIngestFFI.planStorage(
            fields: fieldMap,
            personID: planPersonID,
            profileSchemaKeys: schemaKeys
        )

        let suggestions = mergeExtensionFields(from: storagePlan, into: extracted.suggestions)

        return ScanReviewEnrichment(
            understanding: extracted.understanding,
            personResolution: personResolution,
            storagePlan: storagePlan,
            suggestions: suggestions,
            usedAI: extracted.usedAI,
            displayDocumentType: extracted.displayType,
            openDocumentTypeLabel: extracted.openDocumentTypeLabel,
            plainText: extracted.plainText
        )
    }

    private func mergeExtensionFields(
        from plan: StoragePlanSuggestion?,
        into suggestions: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        guard let plan else { return suggestions }
        var byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })
        for op in plan.operations where op.kind == .upsertExtensionField {
            guard !op.key.isEmpty, !op.value.isEmpty else { continue }
            if byKey[op.key] == nil {
                byKey[op.key] = OcrFieldSuggestion(
                    profileKey: op.key,
                    label: ProfileSchema.label(forExtensionKey: op.key),
                    value: op.value,
                    confidence: "Medium",
                    confidenceScore: 0.68
                )
            }
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }
}

@_silgen_name("dreamwork_fetch_status")
private func dreamwork_fetch_status() -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_string_free")
private func dreamwork_string_free(_ pointer: UnsafeMutablePointer<CChar>?)

@_silgen_name("dreamwork_save_manual_entry")
private func dreamwork_save_manual_entry(
    _ id: UnsafePointer<CChar>?,
    _ displayName: UnsafePointer<CChar>?
) -> Bool

@_silgen_name("dreamwork_read_manual_entry_name")
private func dreamwork_read_manual_entry_name(_ id: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_manual_entry_count")
private func dreamwork_manual_entry_count() -> UInt32

@_silgen_name("dreamwork_manual_entries_json")
private func dreamwork_manual_entries_json() -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_ocr_apply_normalized_json")
private func dreamwork_ocr_apply_normalized_json(_ jsonUtf8: UnsafePointer<CChar>) -> Bool

@_silgen_name("dreamwork_extraction_run_count")
private func dreamwork_extraction_run_count() -> UInt32

@_silgen_name("dreamwork_save_manual_entry_json")
private func dreamwork_save_manual_entry_json(_ jsonUtf8: UnsafePointer<CChar>) -> Bool

@_silgen_name("dreamwork_delete_manual_entry")
private func dreamwork_delete_manual_entry(_ id: UnsafePointer<CChar>) -> Bool

@_silgen_name("dreamwork_ocr_last_document_json")
private func dreamwork_ocr_last_document_json() -> UnsafeMutablePointer<CChar>?

struct RustCoreBridgeService: CoreBridgeService {
    init() {
        RustRepositoryBootstrap.ensureConfiguredForRustCalls()
    }

    func fetchStatus() -> String {
        guard let raw = dreamwork_fetch_status() else {
            return "Rust core unavailable"
        }
        defer { dreamwork_string_free(raw) }
        return String(cString: raw)
    }

    func saveManualEntry(id: String, displayName: String) -> Bool {
        id.withCString { idPtr in
            displayName.withCString { namePtr in
                dreamwork_save_manual_entry(idPtr, namePtr)
            }
        }
    }

    func savePerson(_ person: PersonRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(person),
              let json = String(data: data, encoding: .utf8)
        else {
            return false
        }
        return json.withCString { dreamwork_save_manual_entry_json($0) }
    }

    func deletePerson(id: String) -> Bool {
        id.withCString { dreamwork_delete_manual_entry($0) }
    }

    func readManualEntryName(id: String) -> String? {
        id.withCString { idPtr in
            guard let raw = dreamwork_read_manual_entry_name(idPtr) else {
                return nil
            }
            defer { dreamwork_string_free(raw) }
            return String(cString: raw)
        }
    }

    func manualEntryCount() -> Int {
        Int(dreamwork_manual_entry_count())
    }

    func listPeople() -> [PersonRecord] {
        guard let raw = dreamwork_manual_entries_json() else {
            return []
        }
        defer { dreamwork_string_free(raw) }
        let string = String(cString: raw)
        guard let data = string.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([PersonRecord].self, from: data)) ?? []
    }

    func ingestNormalizedDocumentJSON(_ json: String) -> Bool {
        json.withCString { dreamwork_ocr_apply_normalized_json($0) }
    }

    func extractionRunCount() -> Int {
        Int(dreamwork_extraction_run_count())
    }

    func peekLastNormalizedDocumentJSON() -> String? {
        guard let raw = dreamwork_ocr_last_document_json() else {
            return nil
        }
        defer { dreamwork_string_free(raw) }
        return String(cString: raw)
    }
}

struct MockCoreBridgeService: CoreBridgeService {
    func fetchStatus() -> String {
        "Mock core bridge connected"
    }

    func saveManualEntry(id: String, displayName: String) -> Bool {
        true
    }

    func savePerson(_ person: PersonRecord) -> Bool {
        !person.id.isEmpty
    }

    func deletePerson(id: String) -> Bool {
        true
    }

    func readManualEntryName(id: String) -> String? {
        "Mock Person"
    }

    func manualEntryCount() -> Int {
        1
    }

    func listPeople() -> [PersonRecord] {
        [
            PersonRecord(
                id: "mock-person",
                fields: [PersonRecord.Field(key: "display_name", value: "Mock Person")]
            ),
        ]
    }

    func ingestNormalizedDocumentJSON(_ json: String) -> Bool {
        !json.isEmpty
    }

    func extractionRunCount() -> Int {
        0
    }

    func peekLastNormalizedDocumentJSON() -> String? {
        nil
    }
}
