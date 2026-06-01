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
    /// General-purpose ingest: layout OCR → ONNX field mapping (always on device) → optional GGUF → validators → Rust FFI.
    /// Storage ML is deferred during scan review to avoid loading a second GGUF on device (jetsam).
    func enrichScanReview(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        runStoragePipeline: Bool = false,
        runOnDeviceLLM: Bool = true
    ) async -> ScanReviewEnrichment {
        let people = listPeople()
        let schemaKeys = ProfileSchema.allFields.map(\.key)

        let shouldRunOnDevicePipeline = GenAISettings.provider == .onDevice
        let allowHeavyLLM = runOnDeviceLLM && OnDeviceMemoryGuard.mayRunHeavyInference()

        guard shouldRunOnDevicePipeline else {
            let layoutText = OcrLayoutSerializer.serialize(document: document)
            let plainText = layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            let blocks = OcrLayoutSerializer.orderedBlocks(from: document)
            let labelValuePairsText = OcrLayoutSerializer.labelValuePairs(from: blocks)
                .map { "\($0.label) → \($0.value)" }
                .joined(separator: "\n")
            let emptyGraph = DocumentKnowledgeGraph.buildIdentityGraph(
                from: [],
                documentType: "other"
            )
            return ScanReviewEnrichment(
                understanding: nil,
                personResolution: nil,
                storagePlan: nil,
                suggestions: [],
                usedAI: false,
                displayDocumentType: .other,
                openDocumentTypeLabel: "Document",
                plainText: plainText,
                mappingNotice: nil,
                usedMachineReadablePayload: false,
                usedHeuristicFallback: false,
                identityGraph: emptyGraph,
                autofillPayload: emptyGraph.autofillPayload,
                pipelineTrace: ["ocr:vision.en.v1", "extract:skipped:provider_off", "storage:deferred:scan_review"],
                ocrModelInput: OcrLayoutSerializer.modelInput(document: document),
                ocrLabelValuePairs: labelValuePairsText,
                standardizedOutput: nil,
                fieldsRequiringReview: [],
                heavyLLMDeferred: false,
                ranFullOnDevicePipeline: false
            )
        }

        let extracted = await Task.detached(priority: .utility) {
            await DocumentIntelligencePipeline.extract(
                document: document,
                fileURL: fileURL,
                allowHeavyLLM: allowHeavyLLM
            )
        }.value
        if allowHeavyLLM {
            LlamaRuntime.releaseCachedModel()
        }

        let fieldMap = CoreIngestHTTPClient.fieldMap(from: extracted.suggestions)
        let personResolution = CoreIngestFFI.resolvePerson(fields: fieldMap, people: people)

        let suggestions = extracted.suggestions
        let identityGraph = DocumentKnowledgeGraph.buildIdentityGraph(
            from: suggestions,
            documentType: extracted.understanding?.documentType ?? extracted.openDocumentTypeLabel
        )

        var mappingNotice = extracted.mappingNotice
        var storagePlan: StoragePlanSuggestion?
        var pipelineTrace = extracted.pipelineTrace

        let heavyLLMDeferred: Bool
        let ranFullOnDevicePipeline: Bool

        if runOnDeviceLLM {
            pipelineTrace.append(allowHeavyLLM ? "llm:phase:auto_complete" : "llm:phase:auto_light_only")
            heavyLLMDeferred = !allowHeavyLLM
            ranFullOnDevicePipeline = allowHeavyLLM
            if !allowHeavyLLM {
                pipelineTrace.append("llm:heavy:deferred:\(OnDeviceMemoryGuard.skipTraceToken)")
                mappingNotice = [
                    mappingNotice,
                    OnDeviceMLPolicy.autoGGUFDeferredNotice,
                    OnDeviceMemoryGuard.userFacingSkipNotice
                ].compactMap { $0 }.joined(separator: "\n")
            }
        } else {
            pipelineTrace.append("llm:phase:light_only")
            heavyLLMDeferred = OnDeviceMLPolicy.allowsAutomaticInferenceOnScan
                && !OnDeviceMemoryGuard.mayRunHeavyInference()
            ranFullOnDevicePipeline = false
            if heavyLLMDeferred {
                pipelineTrace.append("llm:heavy:deferred:\(OnDeviceMemoryGuard.skipTraceToken)")
                mappingNotice = [
                    mappingNotice,
                    OnDeviceMLPolicy.autoGGUFDeferredNotice,
                    OnDeviceMemoryGuard.userFacingSkipNotice
                ].compactMap { $0 }.joined(separator: "\n")
            }
        }

        if runStoragePipeline {
            let planPersonID: String? = {
                guard let resolution = personResolution,
                      resolution.resolution == .matchExisting,
                      let id = resolution.personID
                else { return nil }
                return id
            }()
            storagePlan = CoreIngestFFI.planStorage(
                fields: fieldMap,
                personID: planPersonID,
                profileSchemaKeys: schemaKeys,
                documentType: extracted.understanding?.documentType ?? extracted.openDocumentTypeLabel
            )
            LlamaRuntime.releaseCachedModel()

            if let plan = storagePlan,
               plan.summary.plannerStatus != "storage_planner_active"
            {
                mappingNotice = [
                    mappingNotice,
                    "The local ML storage planner failed. No rules-only SQLite routing fallback was used; install the storage planner model or retry after extraction succeeds."
                ].compactMap { $0 }.joined(separator: "\n")
            } else if storagePlan == nil {
                mappingNotice = [
                    mappingNotice,
                    "The local ML storage planner bridge failed. No rules-only SQLite routing fallback was used."
                ].compactMap { $0 }.joined(separator: "\n")
            }
            if var plan = storagePlan {
                pipelineTrace.append("storage:\(plan.summary.plannerEngine):\(plan.summary.plannerStatus)")
                if plan.summary.plannerStatus == "storage_planner_active",
                   let apply = CoreIngestFFI.applyStoragePlan(plan)
                {
                    storagePlan = StoragePlanSuggestion(
                        storageTarget: plan.storageTarget,
                        schemaActions: plan.schemaActions,
                        operations: plan.operations,
                        summary: plan.summary,
                        applyResult: apply
                    )
                    pipelineTrace.append("storage_apply:\(apply.status)")
                    if !apply.applied {
                        mappingNotice = [
                            mappingNotice,
                            "The local ML storage planner produced a plan but SQLite apply failed (\(apply.status))."
                        ].compactMap { $0 }.joined(separator: "\n")
                    }
                }
            }
        } else {
            pipelineTrace.append("storage:deferred:scan_review")
        }

        return ScanReviewEnrichment(
            understanding: extracted.understanding,
            personResolution: personResolution,
            storagePlan: storagePlan,
            suggestions: suggestions,
            usedAI: extracted.usedAI,
            displayDocumentType: extracted.displayType,
            openDocumentTypeLabel: extracted.openDocumentTypeLabel,
            plainText: extracted.plainText,
            mappingNotice: mappingNotice,
            usedMachineReadablePayload: extracted.usedMachineReadablePayload,
            usedHeuristicFallback: extracted.usedHeuristicFallback,
            identityGraph: identityGraph,
            autofillPayload: identityGraph.autofillPayload,
            pipelineTrace: pipelineTrace,
            ocrModelInput: extracted.ocrModelInput,
            ocrLabelValuePairs: extracted.ocrLabelValuePairs,
            standardizedOutput: extracted.standardizedOutput,
            fieldsRequiringReview: extracted.standardizedOutput?.fieldsRequiringReview ?? [],
            heavyLLMDeferred: heavyLLMDeferred,
            ranFullOnDevicePipeline: ranFullOnDevicePipeline
        )
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
