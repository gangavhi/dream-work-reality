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
          height TEXT,
          eye_color TEXT,
          dl_number TEXT,
          dl_issue_mmddyyyy TEXT,
          dl_expiry_mmddyyyy TEXT,
          dl_state TEXT,
          email TEXT,
          ssn_last4 TEXT,
          mobile_phone TEXT,
          insurance_provider TEXT,
          policy_number TEXT,
          address1 TEXT,
          address2 TEXT,
          city TEXT,
          state TEXT,
          postal_code TEXT,
          updated_at REAL NOT NULL
        );
        """)

        // If the DB already existed before these columns were added, ensure they exist.
        // Ignore errors (SQLite doesn't support IF NOT EXISTS for ADD COLUMN).
        _ = try? db.exec("ALTER TABLE people ADD COLUMN height TEXT;")
        _ = try? db.exec("ALTER TABLE people ADD COLUMN eye_color TEXT;")
        _ = try? db.exec("ALTER TABLE people ADD COLUMN insurance_provider TEXT;")
        _ = try? db.exec("ALTER TABLE people ADD COLUMN policy_number TEXT;")

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

        try db.exec("""
        CREATE TABLE IF NOT EXISTS documents (
          id TEXT PRIMARY KEY,
          person_id TEXT NOT NULL,
          type TEXT NOT NULL,
          number TEXT,
          issue_mmddyyyy TEXT,
          expiry_mmddyyyy TEXT,
          raw_text TEXT,
          captured_at REAL NOT NULL,
          FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
        );
        """)

        try db.exec("""
        CREATE TABLE IF NOT EXISTS genai_fields (
          person_id TEXT NOT NULL,
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          PRIMARY KEY(person_id, key),
          FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
        );
        """)
    }

    func fetchAllPeople() throws -> [PersonProfile] {
        let stmt = try db.prepare("""
        SELECT id, nickname, first_name, last_name, dob_mmddyyyy, height, eye_color,
               dl_number, dl_issue_mmddyyyy, dl_expiry_mmddyyyy, dl_state,
               email, ssn_last4, mobile_phone, insurance_provider, policy_number,
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
            p.height = colText(5)
            p.eyeColor = colText(6)
            p.driverLicenseNumber = colText(7)
            p.driverLicenseIssueMMDDYYYY = colText(8)
            p.driverLicenseExpiryMMDDYYYY = colText(9)
            p.driverLicenseState = colText(10)
            p.email = colText(11)
            p.ssnLast4 = colText(12)
            p.mobilePhone = colText(13)
            p.insuranceProvider = colText(14)
            p.policyNumber = colText(15)
            p.addressLine1 = colText(16)
            p.addressLine2 = colText(17)
            p.city = colText(18)
            p.state = colText(19)
            p.postalCode = colText(20)
            p.updatedAt = Date(timeIntervalSince1970: colDouble(21))

            p.driverLicenses = try fetchDriverLicenses(personID: id)
            p.familyMembers = try fetchFamilyMembers(personID: id)
            p.emergencyContacts = try fetchEmergencyContacts(personID: id)
            p.documents = try fetchDocuments(personID: id)
            p.genAIFields = try fetchGenAIFields(personID: id)

            people.append(p)
        }
        return people
    }

    func upsertPerson(_ person: PersonProfile) throws {
        let stmt = try db.prepare("""
        INSERT INTO people (
          id, nickname, first_name, last_name, dob_mmddyyyy, height, eye_color,
          dl_number, dl_issue_mmddyyyy, dl_expiry_mmddyyyy, dl_state,
          email, ssn_last4, mobile_phone, insurance_provider, policy_number,
          address1, address2, city, state, postal_code,
          updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          nickname=excluded.nickname,
          first_name=excluded.first_name,
          last_name=excluded.last_name,
          dob_mmddyyyy=excluded.dob_mmddyyyy,
          height=excluded.height,
          eye_color=excluded.eye_color,
          dl_number=excluded.dl_number,
          dl_issue_mmddyyyy=excluded.dl_issue_mmddyyyy,
          dl_expiry_mmddyyyy=excluded.dl_expiry_mmddyyyy,
          dl_state=excluded.dl_state,
          email=excluded.email,
          ssn_last4=excluded.ssn_last4,
          mobile_phone=excluded.mobile_phone,
          insurance_provider=excluded.insurance_provider,
          policy_number=excluded.policy_number,
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
        bindText(stmt, 6, person.height)
        bindText(stmt, 7, person.eyeColor)
        bindText(stmt, 8, person.driverLicenseNumber)
        bindText(stmt, 9, person.driverLicenseIssueMMDDYYYY)
        bindText(stmt, 10, person.driverLicenseExpiryMMDDYYYY)
        bindText(stmt, 11, person.driverLicenseState)
        bindText(stmt, 12, person.email)
        bindText(stmt, 13, person.ssnLast4)
        bindText(stmt, 14, person.mobilePhone)
        bindText(stmt, 15, person.insuranceProvider)
        bindText(stmt, 16, person.policyNumber)
        bindText(stmt, 17, person.addressLine1)
        bindText(stmt, 18, person.addressLine2)
        bindText(stmt, 19, person.city)
        bindText(stmt, 20, person.state)
        bindText(stmt, 21, person.postalCode)
        sqlite3_bind_double(stmt, 22, person.updatedAt.timeIntervalSince1970)

        try db.stepDone(stmt)

        try replaceFamilyMembers(personID: person.id, members: person.familyMembers)
        try replaceEmergencyContacts(personID: person.id, contacts: person.emergencyContacts)
        try replaceDriverLicenses(personID: person.id, licenses: person.driverLicenses)
        try replaceDocuments(personID: person.id, documents: person.documents)
        try replaceGenAIFields(personID: person.id, fields: person.genAIFields)
    }

    func deletePerson(id: UUID) throws {
        let stmt = try db.prepare("DELETE FROM people WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        try db.stepDone(stmt)
    }

    func deleteAllPeople() throws {
        // Child tables will cascade if foreign keys are enforced, but we delete explicitly
        // to be robust across SQLite configurations.
        try db.exec("DELETE FROM driver_licenses;")
        try db.exec("DELETE FROM family_members;")
        try db.exec("DELETE FROM emergency_contacts;")
        try db.exec("DELETE FROM documents;")
        try db.exec("DELETE FROM people;")
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

    private func fetchDocuments(personID: UUID) throws -> [ScannedDocument] {
        let stmt = try db.prepare("""
        SELECT id, type, number, issue_mmddyyyy, expiry_mmddyyyy, raw_text, captured_at
        FROM documents
        WHERE person_id = ?
        ORDER BY captured_at DESC;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)

        var out: [ScannedDocument] = []
        while db.stepRow(stmt) {
            func colText(_ i: Int32) -> String? {
                guard let c = sqlite3_column_text(stmt, i) else { return nil }
                return String(cString: c)
            }
            let idStr = colText(0) ?? UUID().uuidString
            let id = UUID(uuidString: idStr) ?? UUID()
            let type = colText(1) ?? "unknown"
            var doc = ScannedDocument(id: id, type: type)
            doc.number = colText(2)
            doc.issueMMDDYYYY = colText(3)
            doc.expiryMMDDYYYY = colText(4)
            doc.rawText = colText(5)
            doc.capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            out.append(doc)
        }
        return out
    }

    private func fetchGenAIFields(personID: UUID) throws -> [String: String] {
        let stmt = try db.prepare("""
        SELECT key, value
        FROM genai_fields
        WHERE person_id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, personID.uuidString)

        var out: [String: String] = [:]
        while db.stepRow(stmt) {
            guard let kC = sqlite3_column_text(stmt, 0),
                  let vC = sqlite3_column_text(stmt, 1) else { continue }
            let k = String(cString: kC).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = String(cString: vC).trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty, !v.isEmpty {
                out[k] = v
            }
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

    private func replaceDocuments(personID: UUID, documents: [ScannedDocument]) throws {
        try deleteAll(table: "documents", personID: personID)
        let stmt = try db.prepare("""
        INSERT INTO documents (id, person_id, type, number, issue_mmddyyyy, expiry_mmddyyyy, raw_text, captured_at)
        VALUES (?,?,?,?,?,?,?,?);
        """)
        defer { sqlite3_finalize(stmt) }
        for d in documents {
            sqlite3_reset(stmt)
            bindText(stmt, 1, d.id.uuidString)
            bindText(stmt, 2, personID.uuidString)
            bindText(stmt, 3, d.type)
            bindText(stmt, 4, d.number)
            bindText(stmt, 5, d.issueMMDDYYYY)
            bindText(stmt, 6, d.expiryMMDDYYYY)
            bindText(stmt, 7, d.rawText)
            sqlite3_bind_double(stmt, 8, d.capturedAt.timeIntervalSince1970)
            try db.stepDone(stmt)
        }
    }

    private func replaceGenAIFields(personID: UUID, fields: [String: String]) throws {
        try deleteAll(table: "genai_fields", personID: personID)
        let stmt = try db.prepare("""
        INSERT INTO genai_fields (person_id, key, value)
        VALUES (?,?,?);
        """)
        defer { sqlite3_finalize(stmt) }
        for (k, v) in fields {
            let kk = k.trimmingCharacters(in: .whitespacesAndNewlines)
            let vv = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if kk.isEmpty || vv.isEmpty { continue }
            sqlite3_reset(stmt)
            bindText(stmt, 1, personID.uuidString)
            bindText(stmt, 2, kk)
            bindText(stmt, 3, vv)
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

