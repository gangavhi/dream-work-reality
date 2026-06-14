import Foundation
import GRDB
import UIKit

/// `processDocument(file, individual_id)` — OCR, embedding, relational tagging inside ACID transactions.
enum DocumentProcessor {
    static func processDocument(
        image: UIImage,
        individualId: String,
        householdId: String,
        documentType: String?,
        database: TrustNestDatabase
    ) async throws -> [HouseholdDocument] {
        let text = try await OCRService.extractText(from: image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessingError.emptyText
        }

        let storedImagePath = try persist(image: image, householdId: householdId, individualId: individualId)
        let chunks = chunk(text: text)

        return try await database.queue.write { db in
            var created: [HouseholdDocument] = []
            for (index, chunk) in chunks.enumerated() {
                    let chunkPath = try persistChunk(
                        chunk,
                        householdId: householdId,
                        individualId: individualId,
                        index: index
                    )
                    let docId = UUID().uuidString
                    let embedding = try EmbeddingService.embed(chunk)
                    let vectorJSON = EmbeddingService.vectorLiteral(embedding)

                    try db.inTransaction {
                        try db.execute(
                            sql: """
                            INSERT INTO documents (doc_id, individual_id, household_id, document_type, file_path)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                docId,
                                individualId,
                                householdId,
                                documentType ?? "scanned_document",
                                chunkPath
                            ]
                        )

                        let rowId = db.lastInsertedRowID
                        try db.execute(
                            sql: """
                            INSERT INTO document_vectors (rowid, embedding)
                            VALUES (?, ?)
                            """,
                            arguments: [rowId, vectorJSON]
                        )
                        return .commit
                    }

                    created.append(
                        HouseholdDocument(
                            docId: docId,
                            individualId: individualId,
                            householdId: householdId,
                            documentType: documentType,
                            filePath: chunkPath
                        )
                    )
                }

                let parentDocId = UUID().uuidString
                let parentEmbedding = try EmbeddingService.embed(text)
                let parentVectorJSON = EmbeddingService.vectorLiteral(parentEmbedding)
                try db.inTransaction {
                    try db.execute(
                        sql: """
                        INSERT INTO documents (doc_id, individual_id, household_id, document_type, file_path)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [parentDocId, individualId, householdId, documentType ?? "scan_image", storedImagePath]
                    )
                    let rowId = db.lastInsertedRowID
                    try db.execute(
                        sql: "INSERT INTO document_vectors (rowid, embedding) VALUES (?, ?)",
                        arguments: [rowId, parentVectorJSON]
                    )
                    return .commit
                }
                created.append(
                    HouseholdDocument(
                        docId: parentDocId,
                        individualId: individualId,
                        householdId: householdId,
                        documentType: documentType,
                        filePath: storedImagePath
                    )
                )
            return created
        }
    }

    /// Duplicate metadata for the same file path when a document applies to multiple members (spec pro-tip).
    static func duplicateDocumentForMember(
        docId: String,
        targetIndividualId: String,
        database: TrustNestDatabase
    ) async throws -> HouseholdDocument {
        return try await database.queue.write { db in
                guard let source = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT doc_id, individual_id, household_id, document_type, file_path
                    FROM documents
                    WHERE doc_id = ?
                    """,
                    arguments: [docId]
                ) else {
                    throw DocumentProcessingError.databaseFailure("Source document not found.")
                }

                let householdId = source["household_id"] as String
                let filePath = source["file_path"] as String
                let documentType = source["document_type"] as String?
                let text = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
                let embedding = try EmbeddingService.embed(text)
                let vectorJSON = EmbeddingService.vectorLiteral(embedding)
                let newDocId = UUID().uuidString

                try db.inTransaction {
                    try db.execute(
                        sql: """
                        INSERT INTO documents (doc_id, individual_id, household_id, document_type, file_path)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            newDocId,
                            targetIndividualId,
                            householdId,
                            documentType,
                            filePath
                        ]
                    )
                    let rowId = db.lastInsertedRowID
                    try db.execute(
                        sql: "INSERT INTO document_vectors (rowid, embedding) VALUES (?, ?)",
                        arguments: [rowId, vectorJSON]
                    )
                    return .commit
                }

                return HouseholdDocument(
                    docId: newDocId,
                    individualId: targetIndividualId,
                    householdId: householdId,
                    documentType: documentType,
                    filePath: filePath
                )
        }
    }

    private static func chunk(text: String, maxLength: Int = 500) -> [String] {
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty { chunks.append(slice) }
            start = end
        }
        return chunks.isEmpty ? [text] : chunks
    }

    private static func persist(image: UIImage, householdId: String, individualId: String) throws -> String {
        let directory = try documentsDirectory(householdId: householdId, individualId: individualId)
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw DocumentProcessingError.invalidImage
        }
        try data.write(to: url)
        return url.path
    }

    private static func persistChunk(
        _ chunk: String,
        householdId: String,
        individualId: String,
        index: Int
    ) throws -> String {
        let directory = try documentsDirectory(householdId: householdId, individualId: individualId)
        let url = directory.appendingPathComponent("chunk-\(index)-\(UUID().uuidString).txt")
        try chunk.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private static func documentsDirectory(householdId: String, individualId: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("TrustNest/Documents", isDirectory: true)
            .appendingPathComponent(householdId, isDirectory: true)
            .appendingPathComponent(individualId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
