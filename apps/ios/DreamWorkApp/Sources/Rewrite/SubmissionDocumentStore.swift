import CryptoKit
import Foundation
import Security

/// Encrypted on-device submission document stash (§5 — no cloud, no SQLite BLOBs).
final class SubmissionDocumentStore {
    static let shared = SubmissionDocumentStore()

    struct Record: Codable, Identifiable, Hashable {
        let id: String
        let personId: String
        let documentType: String
        let displayName: String
        let filePath: String
        let mimeType: String
        let fileExtension: String
        let fileSizeBytes: Int
        let sha256: String
        let scannedAt: Date
        var isCurrent: Bool
    }

    private let indexFileName = "stash_index.json"
    private let keychainAccount = "com.trustnest.submission-doc-aes-key"
    private let overrideRootDirectory: URL?

    private init(overrideRootDirectory: URL? = nil) {
        self.overrideRootDirectory = overrideRootDirectory
    }

    /// Isolated store for unit tests (separate directory + keychain account).
    static func makeForTesting(in directory: URL) -> SubmissionDocumentStore {
        SubmissionDocumentStore(overrideRootDirectory: directory)
    }

    /// Keeps a scan/import file on disk until review save or cancel (encrypted stash happens on save).
    static func stageForReview(from sourceURL: URL) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stagingDir = base.appendingPathComponent("DreamWork/scan_staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let destination = stagingDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private var dreamWorkDirectory: URL {
        if let overrideRootDirectory {
            try? FileManager.default.createDirectory(at: overrideRootDirectory, withIntermediateDirectories: true)
            return overrideRootDirectory
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DreamWork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var keychainAccountName: String {
        if overrideRootDirectory != nil {
            return "\(keychainAccount).test.\(overrideRootDirectory!.lastPathComponent)"
        }
        return keychainAccount
    }

    func save(
        personId: String,
        documentType: String,
        sourceURL: URL,
        personDisplayName: String
    ) throws -> Record {
        let plaintext = try Data(contentsOf: sourceURL)
        let ext = sourceURL.pathExtension.lowercased()
        let mime = mimeType(for: ext)
        let sha = SHA256.hash(data: plaintext).compactMap { String(format: "%02x", $0) }.joined()
        let id = UUID().uuidString
        let relativeDir = "submission_docs/\(personId)/\(documentType)"
        let absoluteDir = dreamWorkDirectory.appendingPathComponent(relativeDir, isDirectory: true)
        try FileManager.default.createDirectory(at: absoluteDir, withIntermediateDirectories: true)

        let historyDir = absoluteDir.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)

        var records = loadIndex()
        for index in records.indices where records[index].personId == personId && records[index].documentType == documentType && records[index].isCurrent {
            records[index].isCurrent = false
            let oldPath = dreamWorkDirectory.appendingPathComponent(records[index].filePath)
            if FileManager.default.fileExists(atPath: oldPath.path) {
                let historyPath = historyDir.appendingPathComponent("\(records[index].id).enc")
                try? FileManager.default.moveItem(at: oldPath, to: historyPath)
                records[index] = Record(
                    id: records[index].id,
                    personId: records[index].personId,
                    documentType: records[index].documentType,
                    displayName: records[index].displayName,
                    filePath: "submission_docs/\(personId)/\(documentType)/history/\(records[index].id).enc",
                    mimeType: records[index].mimeType,
                    fileExtension: records[index].fileExtension,
                    fileSizeBytes: records[index].fileSizeBytes,
                    sha256: records[index].sha256,
                    scannedAt: records[index].scannedAt,
                    isCurrent: false
                )
            }
        }

        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey())
        guard let combined = sealed.combined else {
            throw StoreError.encryptionFailed
        }
        let relativePath = "\(relativeDir)/current.enc"
        let outputURL = dreamWorkDirectory.appendingPathComponent(relativePath)
        try combined.write(to: outputURL, options: .atomic)

        let label = RewriteStashPolicy.displayLabel(for: documentType)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let displayName = "\(label) — \(personDisplayName) — \(formatter.string(from: Date()))"

        let record = Record(
            id: id,
            personId: personId,
            documentType: documentType,
            displayName: displayName,
            filePath: relativePath,
            mimeType: mime,
            fileExtension: ext.isEmpty ? "bin" : ext,
            fileSizeBytes: plaintext.count,
            sha256: sha,
            scannedAt: Date(),
            isCurrent: true
        )
        records.append(record)
        try saveIndex(records)
        return record
    }

    func currentRecords(personId: String) -> [Record] {
        loadIndex().filter { $0.personId == personId && $0.isCurrent }
    }

    func stashedDocumentTypes(personId: String) -> Set<String> {
        Set(currentRecords(personId: personId).map(\.documentType))
    }

    func decryptCurrent(personId: String, documentType: String) throws -> Data {
        guard let record = currentRecords(personId: personId).first(where: { $0.documentType == documentType }) else {
            throw StoreError.notFound
        }
        let url = dreamWorkDirectory.appendingPathComponent(record.filePath)
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: symmetricKey())
    }

    // MARK: - Private

    private enum StoreError: Error {
        case encryptionFailed
        case notFound
    }

    private func indexURL() -> URL {
        dreamWorkDirectory.appendingPathComponent(indexFileName)
    }

    private func loadIndex() -> [Record] {
        let url = indexURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private func saveIndex(_ records: [Record]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: indexURL(), options: .atomic)
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    private func symmetricKey() throws -> SymmetricKey {
        if let overrideRootDirectory {
            return try loadOrCreateFileKey(in: overrideRootDirectory)
        }
        if let existing = try? loadKeyFromKeychain() {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        try saveKeyToKeychain(key.withUnsafeBytes { Data($0) })
        return key
    }

    private func loadOrCreateFileKey(in directory: URL) throws -> SymmetricKey {
        let keyURL = directory.appendingPathComponent(".submission-doc-aes-key")
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try data.write(to: keyURL, options: .atomic)
        return key
    }

    private func loadKeyFromKeychain() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.notFound
        }
        return data
    }

    private func saveKeyToKeychain(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.encryptionFailed }
    }
}
