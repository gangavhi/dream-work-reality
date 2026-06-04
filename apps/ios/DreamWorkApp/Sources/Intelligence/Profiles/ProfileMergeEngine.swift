import Foundation

/// Merges fields from multiple scanned documents into one household person profile.
enum ProfileMergeEngine {
    struct MergeReport: Hashable {
        let mergedPersonID: String
        let mergedFieldKeys: [String]
        let conflictKeys: [String]
        let sourceDocumentTypes: [String]
    }

    /// Merges incoming scan fields into an existing profile, preferring higher-confidence values.
    static func merge(
        existing: PersonRecord,
        suggestions: [OcrFieldSuggestion],
        documentType: String
    ) -> (person: PersonRecord, report: MergeReport) {
        var updates: [String: String] = [:]
        var mergedKeys: [String] = []
        var conflicts: [String] = []

        let existingMap = Dictionary(uniqueKeysWithValues: existing.fields.map { ($0.key, $0.value) })

        for suggestion in suggestions {
            let key = suggestion.profileKey
            let incoming = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !incoming.isEmpty else { continue }

            if let current = existingMap[key], !current.isEmpty, current != incoming {
                if shouldPreferIncoming(suggestion, overExistingValue: current) {
                    updates[key] = incoming
                    mergedKeys.append(key)
                } else {
                    conflicts.append(key)
                }
            } else {
                updates[key] = incoming
                mergedKeys.append(key)
            }
        }

        let person = existing.merged(with: updates)
        return (
            person,
            MergeReport(
                mergedPersonID: person.id,
                mergedFieldKeys: mergedKeys,
                conflictKeys: conflicts,
                sourceDocumentTypes: [documentType]
            )
        )
    }

    /// Combines multiple saved profiles that refer to the same person (passport + license + insurance).
    static func mergeProfiles(_ profiles: [PersonRecord]) -> PersonRecord? {
        guard profiles.count > 1 else { return profiles.first }

        var combined = profiles[0]
        for profile in profiles.dropFirst() {
            let fieldMap = Dictionary(uniqueKeysWithValues: profile.fields.map { ($0.key, $0.value) })
            combined = combined.merged(with: fieldMap)
        }
        return combined
    }

    /// Suggests profiles that should be merged based on identity signals.
    static func findMergeCandidates(
        among people: [PersonRecord],
        for suggestions: [OcrFieldSuggestion],
        resolution: PersonResolutionSuggestion?
    ) -> [String] {
        guard let match = PersonProfileMatcher.matchExistingPerson(
            among: people,
            fieldUpdates: Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) }),
            resolution: resolution
        ) else {
            return []
        }
        return [match.personID]
    }

    private static func shouldPreferIncoming(
        _ suggestion: OcrFieldSuggestion,
        overExistingValue current: String
    ) -> Bool {
        if suggestion.mappingSource == .barcode || suggestion.mappingSource == .mrz {
            return true
        }
        if suggestion.confidenceScore >= 0.85 {
            return true
        }
        if current.count < suggestion.value.count, suggestion.confidenceScore >= 0.72 {
            return true
        }
        return false
    }
}
