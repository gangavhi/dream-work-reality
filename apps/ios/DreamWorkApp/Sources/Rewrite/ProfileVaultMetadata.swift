import Foundation

/// Profile vault extras — consents, aliases, signatures, encrypted upload index (UI read model).
struct ProfileVaultMetadata: Codable, Hashable {
    struct Consents: Codable, Hashable {
        var allowAutofill: Bool
        var allowDocumentScan: Bool

        static let `default` = Consents(allowAutofill: true, allowDocumentScan: true)
    }

    struct UploadedFile: Codable, Hashable, Identifiable {
        let documentId: String
        let documentType: String
        let encryptedStoragePath: String
        let checksum: String
        let createdAt: String

        var id: String { documentId }
    }

    var consents: Consents
    var aliases: [String]
    var storedSignatures: [String]
    var uploadedFiles: [UploadedFile]

    static let empty = ProfileVaultMetadata(
        consents: .default,
        aliases: [],
        storedSignatures: [],
        uploadedFiles: []
    )

    static func uploadedFiles(from records: [SubmissionDocumentStore.Record]) -> [UploadedFile] {
        let formatter = ISO8601DateFormatter()
        return records.map { record in
            UploadedFile(
                documentId: record.id,
                documentType: record.documentType,
                encryptedStoragePath: record.filePath,
                checksum: record.sha256,
                createdAt: formatter.string(from: record.scannedAt)
            )
        }
    }

    static func build(
        personId: String,
        aliases: [String] = [],
        storedSignatures: [String] = [],
        consents: Consents = .default
    ) -> ProfileVaultMetadata {
        let records = SubmissionDocumentStore.shared.currentRecords(personId: personId)
        return ProfileVaultMetadata(
            consents: consents,
            aliases: aliases,
            storedSignatures: storedSignatures,
            uploadedFiles: uploadedFiles(from: records)
        )
    }
}
