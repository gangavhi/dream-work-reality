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
    @Published var showDocumentScanner = false
    @Published var showFileImporter = false
    @Published var pendingScanDocumentType: ScannedDocumentType = .driversLicense

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
        guard coreService.deletePerson(id: id) else { return false }
        refreshStatus()
        return true
    }

    func importDocument(from url: URL, documentType: ScannedDocumentType) async {
        documentImportMessage = nil
        isImportingDocument = true

        let localURL: URL
        do {
            // Picker URLs (especially from Mac → Simulator) must be copied while access is valid.
            localURL = try DocumentImportHelper.makeLocalCopy(of: url)
        } catch {
            isImportingDocument = false
            documentImportMessage = error.localizedDescription
            return
        }

        defer {
            isImportingDocument = false
            try? FileManager.default.removeItem(at: localURL)
        }

        let bridge = coreService
        do {
            let result = try await DocumentTextExtractor.extractAndPersist(from: localURL) { json in
                bridge.ingestNormalizedDocumentJSON(json)
            }
            refreshStatus()
            if result.blockCount == 0 {
                documentImportMessage =
                    "No text was detected in this file. Try a clearer photo or PDF, or enter details manually under People."
                return
            }
            presentScanReview(
                documentType: documentType,
                pageCount: result.pageCount,
                blockCount: result.blockCount
            )
        } catch {
            documentImportMessage = error.localizedDescription
        }
    }

    func presentScanReview(documentType: ScannedDocumentType, pageCount: Int, blockCount: Int) {
        guard let json = coreService.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            documentImportMessage = "OCR finished but review data was unavailable."
            return
        }

        let fullText = OcrFieldSuggester.fullText(from: document)
        let suggestions = OcrFieldSuggester.suggest(from: fullText, documentType: documentType)
        scanReviewPayload = ScanReviewPayload(
            documentType: documentType,
            fullText: fullText,
            ocrBlockCount: blockCount,
            pageCount: pageCount,
            suggestions: suggestions
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
