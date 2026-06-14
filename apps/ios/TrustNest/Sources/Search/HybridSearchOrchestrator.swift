import Foundation
import GRDB

/// Hybrid retrieval: metadata filter first, then semantic ranking via sqlite-vec.
enum HybridSearchOrchestrator {
    static func search(
        query: String,
        householdId: String,
        individualId: String,
        database: TrustNestDatabase,
        limit: Int = 5
    ) async throws -> [SearchCandidate] {
        let queryVector = try EmbeddingService.embed(query)
        let vectorJSON = EmbeddingService.vectorLiteral(queryVector)

        return try await database.queue.read { db in
            // Never perform global search — household_id + individual_id are mandatory filters.
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    d.doc_id AS doc_id,
                    d.file_path AS file_path,
                    d.document_type AS document_type,
                    ranked.distance AS distance
                FROM documents d
                -- Join documents and document_vectors on rowid so each vector aligns with its metadata row.
                INNER JOIN (
                    SELECT rowid, distance
                    FROM document_vectors
                    WHERE embedding MATCH ?
                    ORDER BY distance
                    LIMIT 50
                ) ranked ON d.rowid = ranked.rowid
                WHERE d.household_id = ?
                  AND d.individual_id = ?
                ORDER BY ranked.distance ASC
                LIMIT ?
                """,
                arguments: [vectorJSON, householdId, individualId, limit]
            )

            return try rows.map { row in
                let filePath = row["file_path"] as String
                let excerpt = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
                return SearchCandidate(
                    docId: row["doc_id"] as String,
                    filePath: filePath,
                    documentType: row["document_type"] as String?,
                    distance: row["distance"] as Double,
                    excerpt: String(excerpt.prefix(240))
                )
            }
        }
    }
}
