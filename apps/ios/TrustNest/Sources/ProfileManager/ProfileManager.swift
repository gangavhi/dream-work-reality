import Foundation
import GRDB

/// CRUD for `profiles` — triggered when user taps the ADD node on the TrustNest Wheel.
@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published var lastError: String?

    private let database: TrustNestDatabase

    init(database: TrustNestDatabase) {
        self.database = database
        reload()
    }

    func reload() {
        Task {
            do {
                let householdId = try await database.currentHouseholdId()
                let loaded = try await database.queue.read { db -> [Profile] in
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT individual_id, household_id, name, relationship_type
                        FROM profiles
                        WHERE household_id = ?
                        ORDER BY name COLLATE NOCASE ASC
                        """,
                        arguments: [householdId]
                    )
                    return rows.compactMap { row in
                        guard let relationship = RelationshipType(rawValue: row["relationship_type"] as String) else {
                            return nil
                        }
                        return Profile(
                            individualId: row["individual_id"] as String,
                            householdId: row["household_id"] as String,
                            name: row["name"] as String,
                            relationshipType: relationship
                        )
                    }
                }
                profiles = loaded
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func createProfile(name: String, relationshipType: RelationshipType) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Name is required."
            return
        }

        if relationshipType == .primary, profiles.contains(where: { $0.relationshipType == .primary }) {
            lastError = "This household already has a Primary member."
            return
        }

        Task {
            do {
                let householdId = try await database.currentHouseholdId()
                let profile = Profile(
                    individualId: UUID().uuidString,
                    householdId: householdId,
                    name: trimmed,
                    relationshipType: relationshipType
                )
                try await database.queue.write { db in
                    try db.execute(
                        sql: """
                        INSERT INTO profiles (individual_id, household_id, name, relationship_type)
                        VALUES (?, ?, ?, ?)
                        """,
                        arguments: [
                            profile.individualId,
                            profile.householdId,
                            profile.name,
                            profile.relationshipType.rawValue
                        ]
                    )
                }
                reload()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func profile(for individualId: String) -> Profile? {
        profiles.first { $0.individualId == individualId }
    }
}
