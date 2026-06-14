import Foundation
import GRDB

/// Exact relational + vector schema from docs/full-context.md.
enum DatabaseSchema {
    static let createProfiles = """
    CREATE TABLE IF NOT EXISTS profiles (
        individual_id TEXT PRIMARY KEY,
        household_id TEXT NOT NULL,
        name TEXT NOT NULL,
        relationship_type TEXT CHECK(relationship_type IN ('Primary', 'Spouse', 'Dependent'))
    );
    """

    static let createDocuments = """
    CREATE TABLE IF NOT EXISTS documents (
        doc_id TEXT PRIMARY KEY,
        individual_id TEXT NOT NULL,
        household_id TEXT NOT NULL,
        document_type TEXT,
        file_path TEXT NOT NULL,
        FOREIGN KEY(individual_id) REFERENCES profiles(individual_id)
    );
    """

    static let createDocumentVectors = """
    CREATE VIRTUAL TABLE IF NOT EXISTS document_vectors USING vec0(
        embedding float[768]
    );
    """

    static let createHousehold = """
    CREATE TABLE IF NOT EXISTS household (
        household_id TEXT PRIMARY KEY
    );
    """
}

@_silgen_name("initialize_sqlite3_extensions")
private func initialize_sqlite3_extensions() -> Int32

/// Single-file SQLite + sqlite-vec. All queries scope by `household_id`.
final class TrustNestDatabase: Sendable {
    let queue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        _ = initialize_sqlite3_extensions()

        var config = Configuration()
        config.prepareDatabase { db in
            #if DEBUG
            db.trace { print("TrustNest SQL: \($0)") }
            #endif
        }

        if inMemory {
            queue = try DatabaseQueue(configuration: config)
        } else {
            let url = try Self.databaseURL()
            queue = try DatabaseQueue(path: url.path, configuration: config)
        }

        try queue.write { db in
            try db.execute(sql: DatabaseSchema.createHousehold)
            try db.execute(sql: DatabaseSchema.createProfiles)
            try db.execute(sql: DatabaseSchema.createDocuments)
            try db.execute(sql: DatabaseSchema.createDocumentVectors)
        }
    }

    func currentHouseholdId() async throws -> String {
        if let existing = try await queue.read({ db -> String? in
            try Row.fetchOne(db, sql: "SELECT household_id FROM household LIMIT 1").map { $0["household_id"] as String }
        }) {
            return existing
        }

        let householdId = UUID().uuidString
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO household (household_id) VALUES (?)",
                arguments: [householdId]
            )
        }
        return householdId
    }

    private static func databaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("TrustNest", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("trustnest.sqlite")
    }
}
