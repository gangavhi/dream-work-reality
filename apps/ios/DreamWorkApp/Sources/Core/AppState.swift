import Foundation

enum AppTab: Hashable {
    case scan
    case people
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .scan
    @Published private(set) var statusText: String = "Core service not loaded"
    @Published private(set) var manualEntryCount: Int = 0
    @Published var peopleStore: PeopleStore = PeopleStore()

    private let coreService: CoreBridgeService

    init(coreService: CoreBridgeService) {
        self.coreService = coreService
    }

    func refreshStatus() {
        statusText = coreService.fetchStatus()
        manualEntryCount = coreService.manualEntryCount()
    }

    func saveAndLoadDemoPerson() {
        let id = "person-1"
        let saved = coreService.saveManualEntry(id: id, displayName: "Alex Carter")
        _ = saved ? coreService.readManualEntryName(id: id) : nil
        refreshStatus()
    }

    func openPeople() {
        selectedTab = .people
    }

    func openScan() {
        selectedTab = .scan
    }
}
