import Foundation

/// HTTP client for Stage 1 + Stage 3 ingest endpoints on local `core-api` (port-forward `18081`).
enum CoreIngestHTTPClient {
    static let defaultBaseURL = URL(string: "http://127.0.0.1:18081")!

    private struct UnderstandRequest: Encodable {
        var ocr_text: String
        var document_type_hint: String?
        var profile_schema_keys: [String]?
    }

    private struct UnderstandFieldDTO: Decodable {
        var key: String
        var value: String
        var confidence: Double
    }

    private struct UnderstandResponse: Decodable {
        var document_type: String
        var document_type_confidence: Double
        var issuer_region: String?
        var display_name_hint: String?
        var fields: [UnderstandFieldDTO]?
    }

    private struct ResolveRequest: Encodable {
        var fields: [String: String]
        var existing_persons: [ExistingPersonDTO]
    }

    private struct ExistingPersonDTO: Encodable {
        var person_id: String
        var fields: [String: String]
    }

    private struct ResolveResponse: Decodable {
        var resolution: String
        var person_id: String?
        var confidence: Double
        var candidates: [ResolveCandidateDTO]?
    }

    private struct ResolveCandidateDTO: Decodable {
        var person_id: String
        var score: Double
        var reasons: [String]?
        var reason: String?
    }

    private struct ErrorBody: Decodable {
        var error: String?
        var message: String?
    }

    static func understandDocument(
        ocrText: String,
        documentTypeHint: String?,
        profileSchemaKeys: [String],
        apiKey: String?,
        baseURL: URL = defaultBaseURL,
        timeout: TimeInterval = 45
    ) async -> Result<(DocumentUnderstandingResult, [OcrFieldSuggestion]), IngestError> {
        let url = baseURL.appendingPathComponent("ingest/understand")
        let body = UnderstandRequest(
            ocr_text: ocrText,
            document_type_hint: documentTypeHint,
            profile_schema_keys: profileSchemaKeys.isEmpty ? nil : profileSchemaKeys
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Dreamwork-Openai-Api-Key")
        }
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 503 {
                return .failure(.llmUnavailable)
            }
            guard (200 ..< 300).contains(status) else {
                let message = parseErrorMessage(data) ?? "HTTP \(status)"
                return .failure(.http(status, message))
            }

            let decoded = try JSONDecoder().decode(UnderstandResponse.self, from: data)
            let understanding = DocumentUnderstandingResult(
                documentType: decoded.document_type,
                documentTypeConfidence: decoded.document_type_confidence,
                issuerRegion: decoded.issuer_region,
                displayNameHint: decoded.display_name_hint,
                usedAI: true
            )
            let suggestions = (decoded.fields ?? []).compactMap { field -> OcrFieldSuggestion? in
                let key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return nil }
                let label = ProfileSchema.definition(for: key)?.label ?? key
                return OcrFieldSuggestion(
                    profileKey: key,
                    label: label,
                    value: value,
                    confidence: confidenceLabel(field.confidence)
                )
            }
            return .success((understanding, suggestions))
        } catch let error as IngestError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    static func resolvePerson(
        fields: [String: String],
        people: [PersonRecord],
        baseURL: URL = defaultBaseURL,
        timeout: TimeInterval = 5
    ) async -> PersonResolutionSuggestion? {
        let url = baseURL.appendingPathComponent("ingest/resolve-person")
        let existing = people.map { person in
            ExistingPersonDTO(
                person_id: person.id,
                fields: Dictionary(
                    uniqueKeysWithValues: person.fields.map { ($0.key, $0.value) }
                )
            )
        }
        let body = ResolveRequest(fields: fields, existing_persons: existing)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(status) else { return nil }
            let decoded = try JSONDecoder().decode(ResolveResponse.self, from: data)
            let resolution = PersonResolutionKind(rawValue: decoded.resolution) ?? .ambiguous
            let candidates = (decoded.candidates ?? []).map { row in
                let reasons = row.reasons ?? (row.reason.map { [$0] } ?? [])
                return PersonResolutionCandidate(
                    personID: row.person_id,
                    score: row.score,
                    reasons: reasons
                )
            }
            return PersonResolutionSuggestion(
                resolution: resolution,
                personID: decoded.person_id,
                confidence: decoded.confidence,
                candidates: candidates
            )
        } catch {
            return nil
        }
    }

    /// `trusted` wins on key conflicts; `supplemental` only fills missing keys or beats lower confidence.
    static func mergeSuggestions(trusted: [OcrFieldSuggestion], supplemental: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for item in trusted {
            byKey[item.profileKey] = item
        }
        for item in supplemental {
            if let existing = byKey[item.profileKey] {
                if confidenceRank(item.confidence) > confidenceRank(existing.confidence) {
                    byKey[item.profileKey] = item
                }
            } else {
                byKey[item.profileKey] = item
            }
        }
        return byKey.values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Backward-compatible argument order: primary mapping first, heuristics second.
    static func mergeSuggestions(heuristic: [OcrFieldSuggestion], ai: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        mergeSuggestions(trusted: ai, supplemental: heuristic)
    }

    static func fieldMap(from suggestions: [OcrFieldSuggestion]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
    }

    private static func confidenceLabel(_ value: Double) -> String {
        switch value {
        case 0.85...: return "High"
        case 0.6...: return "Medium"
        default: return "Low"
        }
    }

    private static func confidenceRank(_ label: String) -> Int {
        switch label {
        case "High": return 3
        case "Medium": return 2
        default: return 1
        }
    }

    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return parsed.message ?? parsed.error
    }
}

enum IngestError: Error {
    case llmUnavailable
    case http(Int, String)
    case transport(String)
}
