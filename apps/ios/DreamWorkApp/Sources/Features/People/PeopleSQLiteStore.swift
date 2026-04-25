import Foundation
import SQLite3

@MainActor
final class PeopleSQLiteStore {
    // Swift doesn't always import SQLITE_TRANSIENT; define it explicitly.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let db: SQLiteDB

    init(dbPath: String) throws {
        db = try SQLiteDB(path: dbPath)
        try migrate()
    }

    private func migrate() throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS people (
          id TEXT PRIMARY KEY,
          nickname TEXT NOT NULL,
          first_name TEXT,
          last_name TEXT,
          dob_mmddyyyy TEXT,
          dl_number TEXT,
          dl_issue_mmddyyyy TEXT,
          dl_expiry_mmddyyyy TEXT,
          dl_state TEXT,
          email TEXT,
          ssn_last4 TEXT,
          mobile_phone TEXT,
          address1 TEXT,
          address2 TEXT,
          city TEXT,
          state TEXT,
          postal_code TEXT,
          updated_at REAL NOT NULL
        );
        """)

        try db.exec("""
        CREATE TABLE IF NOT EXISTS driver_licenses (
          id TEXT PRIMARY KEY,
          person_id TEXT NOT NULL,
          number TEXT,
          state TEXT,
          issue_mmddyyyy TEXT,
          expiry_mmddyyyy TEXT,
          is_active INTEGER NOT NULL,
          captured_at REAL NOT NULL,
          FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
        );
        """)

        try db.exec("""
        CREATE TABLE IF NOT EXISTS family_members (
          id TEXT PRIMARY KEY,
          person_id TEXT NOT NULL,
          name TEXT NOT NULL,
          relationship TEXT,
          dob_mmddyyyy TEXT,
          phone TEXT,
          FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
        );
        """)

        try db.exec("""
        CREATE TABLE IF NOT EXISTS emergency_contacts (
          id TEXT PRIMARY KEY,
          person_id TEXT NOT NULL,
          name TEXT NOT NULL,
          relationship TEXT,
          phone TEXT,
          FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
        );
        """)
    }

    func fetchAllPeople() throws -> [PersonProfile] {
        let stmt = try db.prepare("""
        SELECT id, nickname, first_name, last_name, dob_mmddyyyy,
               dl_number, dl_issue_mmddyyyy, dl_expiry_mmddyyyy, dl_state,
               email, ssn_last4, mobile_phone,
               address1, address2, city, state, postal_code,
               updated_at
        FROM people
        ORDER BY updated_at DESC;
        """)
        defer { sqlite3_finalize(stmt) }

        var people: [PersonProfile] = []
        while db.stepRow(stmt) {
            func colText(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }
            func colDouble(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }

            let idStr = colText(0) ?? UUID().uuidString
            let id = UUID(uuidString: idStr) ?? UUID()
            var p = PersonProfile(id: id, nickname: colText(1) ?? "")
            p.firstName = colText(2)
            p.lastName = colText(3)
            p.dateOfBirthMMDDYYYY = colText(4)
            p.driverLicenseNumber = colText(5)
            p.driverLicenseIssueMMDDYYYY = colText(6)
            p.driverLicenseExpiryMMDDYYYY = colText(7)
            p.driverLicenseState = colText(8)
            p.email = colText(9)
            p.ssnLast4 = colText(10)
            p.mobilePhone = colText(11)
            p.addressLine1 = colText(12)
            p.addressLine2 = colText(13)
            p.city = colText(14)
            p.state = colText(15)
            p.postalCode = colText(16)
            p.updatedAt = Date(timeIntervalSince1970: colDouble(17))

            p.driverLicenses = try fetchDriverLicenses(personID: id)
            p.familyMembers = try fetchFamilyMembers(personID: id)
            p.emergencyContacts = try fetchEmergencyContacts(personID: id)

            people.append(p)
        }
        return people
    }

    func upsertPerson(_ person: PersonProfile) throws {
        let stmt = try db.prepare("""
        INSERT INTO people (
          id, nickname, first_name, last_name, dob_mmddyyyy,
          dl_number, dl_issue_mmddyyyy, dl_expiry_mmddyyyy, dl_state,
          email, ssn_last4, mobile_phone,
          address1, address2, city, state, postal_code,
          updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          nickname=excluded.nickname,
          first_name=excluded.first_name,
          last_name=excluded.last_name,
          dob_mmddyyyy=excluded.dob_mmddyyyy,
          dl_number=excluded.dl_number,
          dl_issue_mmddyyyy=excluded.dl_issue_mmddyyyy,
          dl_expiry_mmddyyyy=excluded.dl_expiry_mmddyyyy,
          dl_state=excluded.dl_state,
          email=excluded.email,
          ssn_last4=excluded.ssn_last4,
          mobile_phone=excluded.mobile_phone,
          address1=excluded.address1,
          address2=excluded.address2,
          city=excluded.city,
          state=excluded.state,
          postal_code=excluded.postal_code,
          updated_at=excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, person.id.uuidString)
        bindText(stmt, 2, person.nickname)
        bindText(stmt, 3, person.firstName)
        bindText(stmt, 4, person.lastName)
        bindText(stmt, 5, person.dateOfBirthMMDDYYYY)
        bindText(stmt, 6, person.driverLicenseNumber)
        bindText(stmt, 7, person.driverLicenseIssueMMDDYYYY)
        bindText(stmt, 8, person.driverLicenseExpiryMMDDYYYY)
        bindText(stmt, 9, person.driverLicenseState)
        bindText(stmt, 10, person.email)
        bindText(stmt, 11, person.ssnLast4)
        bindText(stmt, 12, person.mobilePhone)
        bindText(stmt, 13, person.addressLine1)
        bindText(stmt, 14, person.addressLine2)
        bindText(stmt, 15, person.city)
        bindText(stmt, 16, person.state)
        bindText(stmt, 17, person.postalCode)
        sqlite3_bind_double(stmt, 18, person.updatedAt.timeIntervalSince1970)

        try db.stepDone(stmt)

        try replaceFamilyMembers(personID: person.id, members: person.familyMembers)
        try replaceEmergencyContacts(personID: person.id, contacts: person.emergencyContacts)
        try replaceDriverLicenses(personID: person.id, licenses: person.driverLicenses)
    }

    func deletePerson(id: UUID) throws {
        let stmt = try db.prepare("DELETE FROM people WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        try db.stepDone(stmt)
    }

    // MARK: - Child tables

    private func fetchDriverLicenses(personID: UUID) throws -> [DriverLicense] {
        let stmt = try db.prepare("""
        SELECT id, number, state, issue_mmddyyyy, expiry_mmddyyyy, is_active, captured_at
        FROM driver_licenses
        WHERE person_id = ?
        ORDER BY captured_at DESC;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)

        var out: [DriverLicense] = []
        while db.stepRow(stmt) {
            func colText(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }
            let idStr = colText(0) ?? UUID().uuidString
            let id = UUID(uuidString: idStr) ?? UUID()
            var dl = DriverLicense(id: id)
            dl.number = colText(1)
            dl.state = colText(2)
            dl.issueMMDDYYYY = colText(3)
            dl.expiryMMDDYYYY = colText(4)
            dl.isActive = sqlite3_column_int(stmt, 5) != 0
            dl.capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            out.append(dl)
        }
        return out
    }

    private func fetchFamilyMembers(personID: UUID) throws -> [FamilyMember] {
        let stmt = try db.prepare("""
        SELECT id, name, relationship, dob_mmddyyyy, phone
        FROM family_members
        WHERE person_id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)

        var out: [FamilyMember] = []
        while db.stepRow(stmt) {
            func colText(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }
            let idStr = colText(0) ?? UUID().uuidString
            let id = UUID(uuidString: idStr) ?? UUID()
            var fm = FamilyMember(id: id, name: colText(1) ?? "")
            fm.relationship = colText(2)
            fm.dateOfBirthMMDDYYYY = colText(3)
            fm.phone = colText(4)
            out.append(fm)
        }
        return out
    }

    private func fetchEmergencyContacts(personID: UUID) throws -> [EmergencyContact] {
        let stmt = try db.prepare("""
        SELECT id, name, relationship, phone
        FROM emergency_contacts
        WHERE person_id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)

        var out: [EmergencyContact] = []
        while db.stepRow(stmt) {
            func colText(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }
            let idStr = colText(0) ?? UUID().uuidString
            let id = UUID(uuidString: idStr) ?? UUID()
            var ec = EmergencyContact(id: id, name: colText(1) ?? "")
            ec.relationship = colText(2)
            ec.phone = colText(3)
            out.append(ec)
        }
        return out
    }

    private func replaceFamilyMembers(personID: UUID, members: [FamilyMember]) throws {
        try deleteAll(table: "family_members", personID: personID)
        let stmt = try db.prepare("""
        INSERT INTO family_members (id, person_id, name, relationship, dob_mmddyyyy, phone)
        VALUES (?,?,?,?,?,?);
        """)
        defer { sqlite3_finalize(stmt) }
        for m in members {
            sqlite3_reset(stmt)
            bindText(stmt, 1, m.id.uuidString)
            bindText(stmt, 2, personID.uuidString)
            bindText(stmt, 3, m.name)
            bindText(stmt, 4, m.relationship)
            bindText(stmt, 5, m.dateOfBirthMMDDYYYY)
            bindText(stmt, 6, m.phone)
            try db.stepDone(stmt)
        }
    }

    private func replaceEmergencyContacts(personID: UUID, contacts: [EmergencyContact]) throws {
        try deleteAll(table: "emergency_contacts", personID: personID)
        let stmt = try db.prepare("""
        INSERT INTO emergency_contacts (id, person_id, name, relationship, phone)
        VALUES (?,?,?,?,?);
        """)
        defer { sqlite3_finalize(stmt) }
        for c in contacts {
            sqlite3_reset(stmt)
            bindText(stmt, 1, c.id.uuidString)
            bindText(stmt, 2, personID.uuidString)
            bindText(stmt, 3, c.name)
            bindText(stmt, 4, c.relationship)
            bindText(stmt, 5, c.phone)
            try db.stepDone(stmt)
        }
    }

    private func replaceDriverLicenses(personID: UUID, licenses: [DriverLicense]) throws {
        try deleteAll(table: "driver_licenses", personID: personID)
        let stmt = try db.prepare("""
        INSERT INTO driver_licenses (id, person_id, number, state, issue_mmddyyyy, expiry_mmddyyyy, is_active, captured_at)
        VALUES (?,?,?,?,?,?,?,?);
        """)
        defer { sqlite3_finalize(stmt) }
        for dl in licenses {
            sqlite3_reset(stmt)
            bindText(stmt, 1, dl.id.uuidString)
            bindText(stmt, 2, personID.uuidString)
            bindText(stmt, 3, dl.number)
            bindText(stmt, 4, dl.state)
            bindText(stmt, 5, dl.issueMMDDYYYY)
            bindText(stmt, 6, dl.expiryMMDDYYYY)
            sqlite3_bind_int(stmt, 7, dl.isActive ? 1 : 0)
            sqlite3_bind_double(stmt, 8, dl.capturedAt.timeIntervalSince1970)
            try db.stepDone(stmt)
        }
    }

    private func deleteAll(table: String, personID: UUID) throws {
        let stmt = try db.prepare("DELETE FROM \(table) WHERE person_id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)
        try db.stepDone(stmt)
    }

    // MARK: - Binding helpers

    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }
}

