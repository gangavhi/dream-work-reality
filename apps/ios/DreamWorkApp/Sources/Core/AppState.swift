import Foundation

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

    func importDocument(from url: URL) async {
        documentImportMessage = nil
        isImportingDocument = true
        defer { isImportingDocument = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bridge = coreService
        do {
            let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
                bridge.ingestNormalizedDocumentJSON(json)
            }
            refreshStatus()
            documentImportMessage =
                "Imported \(summary.pageCount) page(s), \(summary.blockCount) text region(s). SQLite extraction_run total: \(extractionRunCount)."
        } catch {
            documentImportMessage = error.localizedDescription
        }
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

    func seedSamplePeople() {
        _ = coreService.saveManualEntry(id: "person-1", displayName: "Alex Carter")
        _ = coreService.saveManualEntry(id: "person-2", displayName: "Sam Rivera")
        refreshStatus()
    }
}
