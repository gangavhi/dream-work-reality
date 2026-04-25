import Foundation

@MainActor
final class PeopleStore: ObservableObject {
    @Published private(set) var people: [PersonProfile] = []
    @Published var selectedPersonID: UUID?

    private let storageKey = "people.profiles.v1"

    init() {
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
        persist()
    }

    func delete(_ id: UUID) {
        people.removeAll(where: { $0.id == id })
        if selectedPersonID == id {
            selectedPersonID = people.first?.id
        }
        persist()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data) else {
            people = []
            return
        }
        people = decoded.sorted(by: { $0.updatedAt > $1.updatedAt })
        if selectedPersonID == nil {
            selectedPersonID = people.first?.id
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

