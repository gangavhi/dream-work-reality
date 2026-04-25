import Foundation
import SQLite3

enum SQLiteDBError: Error, LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let s): return s
        case .execFailed(let s): return s
        case .prepareFailed(let s): return s
        case .stepFailed(let s): return s
        }
    }
}

/// Minimal SQLite helper (no external deps).
final class SQLiteDB {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteDBError.openFailed("sqlite open failed: \(msg)")
        }
        db = handle

        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func exec(_ sql: String) throws {
        guard let db else { throw SQLiteDBError.execFailed("db closed") }
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(err)
            throw SQLiteDBError.execFailed(msg)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw SQLiteDBError.prepareFailed("db closed") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    func stepDone(_ stmt: OpaquePointer) throws {
        guard let db else { throw SQLiteDBError.stepFailed("db closed") }
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw SQLiteDBError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func stepRow(_ stmt: OpaquePointer) -> Bool {
        sqlite3_step(stmt) == SQLITE_ROW
    }
}

