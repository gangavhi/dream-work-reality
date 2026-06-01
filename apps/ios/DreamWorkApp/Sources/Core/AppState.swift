import Foundation
import SwiftUI

enum AppTab: Hashable {
    case home
    case people
    case forms
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published private(set) var statusText: String = "Core service not loaded"
    @Published private(set) var manualEntryCount: Int = 0
    @Published private(set) var selectedPersonName: String = "No person loaded"
    @Published private(set) var people: [PersonRecord] = []
    @Published private(set) var extractionRunCount: Int = 0
    @Published private(set) var isImportingDocument = false
    @Published var documentImportMessage: String?
    @Published var scanReviewPayload: ScanReviewPayload?
    @Published private(set) var isRunningOnDeviceExtraction = false
    @Published var showDocumentScanner = false
    @Published var showFileImporter = false

    private var pendingScanDocument: VisionOcrAdapter.NormalizedDocument?
    private var pendingScanPageCount: Int = 0
    private var pendingScanBlockCount: Int = 0

    private let coreService: CoreBridgeService

    init(coreService: CoreBridgeService) {
        self.coreService = coreService
    }

    func refreshPeopleList() {
        people = coreService.listPeople()
    }

    func refreshStatus() {
        statusText = coreService.fetchStatus()
        manualEntryCount = coreService.manualEntryCount()
        extractionRunCount = coreService.extractionRunCount()
        refreshPeopleList()
    }

    func savePerson(_ person: PersonRecord) -> Bool {
        guard coreService.savePerson(person) else { return false }
        refreshStatus()
        return true
    }

    func deletePerson(id: String) -> Bool {
        let personName = people.first(where: { $0.id == id })?.displayTitle
        guard coreService.deletePerson(id: id) else { return false }
        DocumentFingerprintStore.removeEntries(forPersonID: id, personName: personName)
        refreshStatus()
        return true
    }

    /// Imports a document downloaded from a Mac-hosted HTTP folder (Simulator testing).
    func importDocument(fromRemoteURL url: URL) async {
        do {
            let localURL = try await LaptopDocumentListing.downloadToTemporaryFile(from: url)
            await importDocument(from: localURL, urlIsTemporaryCopy: true)
        } catch {
            documentImportMessage = error.localizedDescription
        }
    }

    /// Imports a document from a URL. Document type is inferred from OCR after extraction.
    func importDocument(
        from url: URL,
        urlIsTemporaryCopy: Bool = false
    ) async {
        documentImportMessage = nil
        isImportingDocument = true

        let localURL: URL
        let shouldDeleteLocalCopy: Bool
        do {
            if urlIsTemporaryCopy {
                localURL = url
                shouldDeleteLocalCopy = true
            } else {
                // Picker URLs must be copied while security-scoped access is still valid.
                localURL = try DocumentImportHelper.makeLocalCopy(of: url)
                shouldDeleteLocalCopy = true
            }
        } catch {
            isImportingDocument = false
            documentImportMessage = error.localizedDescription
            return
        }

        defer {
            isImportingDocument = false
            if shouldDeleteLocalCopy {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        let bridge = coreService

        do {
            let result = try await DocumentTextExtractor.extractAndPersist(from: localURL) { json in
                bridge.ingestNormalizedDocumentJSON(json)
            }
            refreshStatus()

            let layoutText = OcrLayoutSerializer.serialize(document: result.document)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if layoutText.isEmpty {
                documentImportMessage =
                    "No text was detected in this file. Try a clearer photo or PDF, or enter details manually under People."
                return
            }

            await presentScanReview(
                document: result.document,
                fileURL: localURL,
                pageCount: result.pageCount,
                blockCount: result.blockCount
            )
        } catch {
            documentImportMessage = error.localizedDescription
        }
    }

    func presentScanReview(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        pageCount: Int,
        blockCount: Int
    ) async {
        pendingScanDocument = document
        pendingScanPageCount = pageCount
        pendingScanBlockCount = blockCount

        isRunningOnDeviceExtraction = GenAISettings.provider == .onDevice
        defer { isRunningOnDeviceExtraction = false }

        let runAutomaticFullPipeline = GenAISettings.provider == .onDevice
            && OnDeviceMLPolicy.allowsAutomaticInferenceOnScan
        let enrichment = await coreService.enrichScanReview(
            document: document,
            fileURL: fileURL,
            runOnDeviceLLM: runAutomaticFullPipeline
        )
        applyScanReviewEnrichment(
            enrichment,
            pageCount: pageCount,
            blockCount: blockCount
        )
    }

    /// User-initiated on-device extraction (safe default on physical iPhone).
    func runOnDeviceExtractionForCurrentScan() async {
        guard let document = pendingScanDocument else { return }
        guard GenAISettings.provider == .onDevice else { return }
        guard !isRunningOnDeviceExtraction else { return }

        isRunningOnDeviceExtraction = true
        defer { isRunningOnDeviceExtraction = false }

        let enrichment = await coreService.enrichScanReview(
            document: document,
            runOnDeviceLLM: true
        )
        guard scanReviewPayload != nil else { return }

        var signals: [String] = []
        if enrichment.usedMachineReadablePayload { signals.append("barcode or MRZ") }
        if enrichment.usedAI { signals.append("on-device extraction") }
        if enrichment.usedHeuristicFallback { signals.append("estimated heuristics") }
        if signals.isEmpty { signals = ["layout heuristics"] }

        applyScanReviewEnrichment(
            enrichment,
            pageCount: pendingScanPageCount,
            blockCount: pendingScanBlockCount,
            classificationSignals: signals
        )
    }

    func clearPendingScanSession() {
        pendingScanDocument = nil
        pendingScanPageCount = 0
        pendingScanBlockCount = 0
    }

    private func applyScanReviewEnrichment(
        _ enrichment: ScanReviewEnrichment,
        pageCount: Int,
        blockCount: Int,
        classificationSignals: [String]? = nil
    ) {
        var signals = classificationSignals ?? []
        if signals.isEmpty {
            if enrichment.usedMachineReadablePayload { signals.append("barcode or MRZ") }
            if enrichment.usedAI { signals.append("on-device extraction") }
            if enrichment.usedHeuristicFallback { signals.append("estimated heuristics") }
            if signals.isEmpty { signals = ["layout heuristics"] }
        }

        scanReviewPayload = ScanReviewPayload(
            detectedDocumentType: enrichment.displayDocumentType,
            openDocumentTypeLabel: enrichment.openDocumentTypeLabel,
            classificationConfidence: enrichment.understanding?.documentTypeConfidence ?? 0.55,
            classificationSignals: signals,
            fullText: enrichment.plainText,
            ocrBlockCount: blockCount,
            pageCount: pageCount,
            suggestions: enrichment.suggestions,
            understanding: enrichment.understanding,
            personResolution: enrichment.personResolution,
            storagePlan: enrichment.storagePlan,
            usedAI: enrichment.usedAI,
            mappingNotice: enrichment.mappingNotice,
            usedMachineReadablePayload: enrichment.usedMachineReadablePayload,
            usedHeuristicFallback: enrichment.usedHeuristicFallback,
            identityGraph: enrichment.identityGraph,
            autofillPayload: enrichment.autofillPayload,
            pipelineTrace: enrichment.pipelineTrace,
            ocrModelInput: enrichment.ocrModelInput,
            ocrLabelValuePairs: enrichment.ocrLabelValuePairs,
            standardizedOutput: enrichment.standardizedOutput,
            fieldsRequiringReview: enrichment.fieldsRequiringReview,
            prefilledPerson: nil,
            showManualExtractionRetry: OnDeviceMLPolicy.shouldShowManualExtractionRetry(
                heavyLLMDeferred: enrichment.heavyLLMDeferred,
                suggestionsEmpty: enrichment.suggestions.isEmpty
            )
        )
    }

    func saveAndLoadDemoPerson() {
        let id = "person-1"
        let saved = coreService.saveManualEntry(id: id, displayName: "Alex Carter")
        if saved, let name = coreService.readManualEntryName(id: id) {
            selectedPersonName = name
        } else {
            selectedPersonName = "Failed to load person"
        }
        refreshStatus()
    }

    func openPeople() {
        selectedTab = .people
    }

    func seedSamplePeople() {
        _ = savePerson(
            PersonRecord.empty(id: "person-1")
                .withValue("Alex Carter", for: ProfileFieldKey.displayName)
                .withValue(HouseholdRelationship.selfMember.rawValue, for: ProfileFieldKey.relationship)
        )
        _ = savePerson(
            PersonRecord.empty(id: "person-2")
                .withValue("Sam Rivera", for: ProfileFieldKey.displayName)
                .withValue(HouseholdRelationship.child.rawValue, for: ProfileFieldKey.relationship)
        )
        refreshStatus()
    }
}
