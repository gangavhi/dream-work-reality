import Foundation

@MainActor
final class PeopleStore: ObservableObject {
    @Published private(set) var people: [PersonProfile] = []
    @Published var selectedPersonID: UUID?

    private let legacyStorageKey = "people.profiles.v1"
    private let selectedPersonKey = "people.selected_person_id.v1"
    private let db: PeopleSQLiteStore

    init() {
        let dbURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DreamWorkApp", isDirectory: true)
            .appendingPathComponent("people.sqlite3")

        try? FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try! PeopleSQLiteStore(dbPath: dbURL.path)

        migrateFromLegacyUserDefaultsIfNeeded()
        load()
    }

    var selectedPerson: PersonProfile? {
        guard let selectedPersonID else { return nil }
        return people.first(where: { $0.id == selectedPersonID })
    }

    func upsert(_ person: PersonProfile, select: Bool = true) {
        if let idx = people.firstIndex(where: { $0.id == person.id }) {
            people[idx] = person
        } else {
            people.insert(person, at: 0)
        }
        if select {
            selectedPersonID = person.id
        }
        persist(person)
    }

    func delete(_ id: UUID) {
        people.removeAll(where: { $0.id == id })
        if selectedPersonID == id {
            selectedPersonID = people.first?.id
        }
        try? db.deletePerson(id: id)
        persistSelectedPerson()
    }

    func load() {
        people = (try? db.fetchAllPeople()) ?? []
        if selectedPersonID == nil, let raw = UserDefaults.standard.string(forKey: selectedPersonKey) {
            selectedPersonID = UUID(uuidString: raw)
        }
        if selectedPersonID == nil {
            selectedPersonID = people.first?.id
        }
    }

    private func persist(_ person: PersonProfile) {
        try? db.upsertPerson(person)
        persistSelectedPerson()
        // Refresh ordering from DB (updated_at sort)
        load()
    }

    private func persistSelectedPerson() {
        if let selectedPersonID {
            UserDefaults.standard.set(selectedPersonID.uuidString, forKey: selectedPersonKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedPersonKey)
        }
    }

    private func migrateFromLegacyUserDefaultsIfNeeded() {
        // If DB already has rows, don't import.
        if let existing = try? db.fetchAllPeople(), !existing.isEmpty {
            return
        }
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data),
              !decoded.isEmpty else {
            return
        }
        for p in decoded {
            try? db.upsertPerson(p)
        }
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
    }
}

