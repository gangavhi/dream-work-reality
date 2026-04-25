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
    @Published var showSchoolIntakeForm: Bool = false
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

    func openSchoolIntakeForm() {
        selectedTab = .forms
        showSchoolIntakeForm = true
    }

    func openPeople() {
        selectedTab = .people
    }
}
