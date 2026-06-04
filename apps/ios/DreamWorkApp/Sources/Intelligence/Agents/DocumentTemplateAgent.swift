import Foundation

/// Template matching is a deterministic fast path between classification and semantic extraction.
/// It keeps common structured documents stable while still allowing unknown forms to use open vocabulary.
enum DocumentTemplateAgent {
    struct Match: Hashable {
        let templateID: String
        let documentType: String
        let confidence: Double
        let signals: [String]
    }

    private struct Definition {
        let id: String
        let documentType: String
        let keywords: [String]
        let fieldKeys: Set<String>
        let coordinateRules: [CoordinateRule]

        init(
            id: String,
            documentType: String,
            keywords: [String],
            fieldKeys: Set<String>,
            coordinateRules: [CoordinateRule] = []
        ) {
            self.id = id
            self.documentType = documentType
            self.keywords = keywords
            self.fieldKeys = fieldKeys
            self.coordinateRules = coordinateRules
        }
    }

    private struct CoordinateRule {
        let profileKey: String
        let label: String
        let region: NormalizedRegion
    }

    private struct NormalizedRegion {
        let minX: Float
        let minY: Float
        let maxX: Float
        let maxY: Float

        func contains(centerOf block: OcrLayoutSerializer.LayoutBlock) -> Bool {
            let cx = block.x + block.width / 2
            let cy = block.y + block.height / 2
            return cx >= minX && cx <= maxX && cy >= minY && cy <= maxY
        }
    }

    private static let threshold = 0.62

    private static let definitions: [Definition] = [
        Definition(
            id: "template.drivers_license.v1",
            documentType: "drivers_license",
            keywords: ["driver license", "drivers license", "license no", "lic no", "date of birth"],
            fieldKeys: [
                ProfileFieldKey.displayName,
                ProfileFieldKey.legalFirstName,
                ProfileFieldKey.legalMiddleName,
                ProfileFieldKey.legalLastName,
                ProfileFieldKey.dateOfBirth,
                ProfileFieldKey.addressLine1,
                ProfileFieldKey.city,
                ProfileFieldKey.state,
                ProfileFieldKey.postalCode,
                ProfileFieldKey.driversLicenseNumber,
                ProfileFieldKey.driversLicenseState,
                ProfileFieldKey.driversLicenseIssueDate,
                ProfileFieldKey.driversLicenseExpiry,
            ],
            coordinateRules: [
                CoordinateRule(
                    profileKey: ProfileFieldKey.legalFirstName,
                    label: "Legal first name",
                    region: NormalizedRegion(minX: 0.08, minY: 0.72, maxX: 0.72, maxY: 0.86)
                ),
                CoordinateRule(
                    profileKey: ProfileFieldKey.legalLastName,
                    label: "Legal last name",
                    region: NormalizedRegion(minX: 0.08, minY: 0.60, maxX: 0.72, maxY: 0.74)
                ),
                CoordinateRule(
                    profileKey: ProfileFieldKey.dateOfBirth,
                    label: "Date of birth",
                    region: NormalizedRegion(minX: 0.08, minY: 0.48, maxX: 0.72, maxY: 0.62)
                ),
                CoordinateRule(
                    profileKey: ProfileFieldKey.driversLicenseNumber,
                    label: "Driver license number",
                    region: NormalizedRegion(minX: 0.08, minY: 0.36, maxX: 0.78, maxY: 0.52)
                ),
            ]
        ),
        Definition(
            id: "template.passport.v1",
            documentType: "passport",
            keywords: ["passport", "surname", "given name", "nationality", "place of birth"],
            fieldKeys: [
                ProfileFieldKey.legalFirstName,
                ProfileFieldKey.legalMiddleName,
                ProfileFieldKey.legalLastName,
                ProfileFieldKey.dateOfBirth,
                ProfileFieldKey.gender,
                ProfileFieldKey.passportNumber,
                ProfileFieldKey.passportCountry,
                ProfileFieldKey.passportExpiry,
                ProfileFieldKey.country,
                "place_of_birth",
                "place_of_issue",
            ]
        ),
        Definition(
            id: "template.insurance_card.v1",
            documentType: "insurance_card",
            keywords: ["insurance", "member id", "subscriber", "policy"],
            fieldKeys: [
                ProfileFieldKey.displayName,
                ProfileFieldKey.insuranceCarrier,
                ProfileFieldKey.insuranceMemberId,
                "group_number",
                "policy_number",
                "subscriber_id",
            ]
        ),
        Definition(
            id: "template.tax_form.v1",
            documentType: "tax_w2",
            keywords: ["w-2", "w2", "wage", "tax year", "employer"],
            fieldKeys: [
                ProfileFieldKey.displayName,
                ProfileFieldKey.legalFirstName,
                ProfileFieldKey.legalLastName,
                ProfileFieldKey.ssn,
                ProfileFieldKey.employerName,
                ProfileFieldKey.taxFormType,
                ProfileFieldKey.taxYear,
            ]
        ),
    ]

    static func match(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        classification: ClassificationAgent.Result
    ) -> Match? {
        let corpus = (layout.layoutText + "\n" + layout.modelInput).lowercased()
        let pairKeys = Set(layout.labelValuePairs.compactMap { pair in
            SemanticFieldLabelMapper.resolve(
                label: pair.label,
                documentTypeHint: classification.openDocumentType
            )?.profileKey
        })

        let ranked = definitions.compactMap { definition -> Match? in
            var score = 0.0
            var signals: [String] = []

            if classification.openDocumentType == definition.documentType {
                score += 0.35
                signals.append("classified:\(definition.documentType)")
            }

            let keywordHits = definition.keywords.filter { corpus.contains($0) }
            if !keywordHits.isEmpty {
                score += min(0.35, Double(keywordHits.count) * 0.1)
                signals.append("keywords:\(keywordHits.prefix(3).joined(separator: ","))")
            }

            let fieldHits = pairKeys.intersection(definition.fieldKeys)
            if !fieldHits.isEmpty {
                score += min(0.35, Double(fieldHits.count) * 0.09)
                signals.append("fields:\(fieldHits.count)")
            }

            let coordinateHits = definition.coordinateRules.filter { rule in
                layout.blocks.contains { rule.region.contains(centerOf: $0) }
            }
            if !coordinateHits.isEmpty {
                score += min(0.35, Double(coordinateHits.count) * 0.09)
                signals.append("coordinates:\(coordinateHits.count)")
            }

            let confidence = min(0.96, score)
            guard confidence >= threshold else { return nil }
            return Match(
                templateID: definition.id,
                documentType: definition.documentType,
                confidence: confidence,
                signals: signals
            )
        }

        return ranked.max { $0.confidence < $1.confidence }
    }

    static func extract(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        match: Match
    ) -> [OcrFieldSuggestion] {
        guard let definition = definitions.first(where: { $0.id == match.templateID }) else {
            return []
        }

        var out = coordinateSuggestions(from: layout.blocks, definition: definition, match: match)
        for pair in allPairs(from: layout) {
            guard let resolved = SemanticFieldLabelMapper.resolve(
                label: pair.label,
                documentTypeHint: match.documentType
            ) else { continue }

            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard isValidTemplateValue(profileKey: resolved.profileKey, value: value, documentType: match.documentType) else {
                continue
            }

            let isKnownTemplateField = definition.fieldKeys.contains(resolved.profileKey)
            let score = isKnownTemplateField ? max(0.88, match.confidence) : 0.78
            out.append(
                OcrFieldSuggestion(
                    profileKey: resolved.profileKey,
                    label: resolved.displayLabel,
                    value: value,
                    confidence: score >= 0.85 ? "High" : "Medium",
                    confidenceScore: score,
                    mappingSource: .template
                )
            )
        }
        return dedupe(out)
    }

    private static func coordinateSuggestions(
        from blocks: [OcrLayoutSerializer.LayoutBlock],
        definition: Definition,
        match: Match
    ) -> [OcrFieldSuggestion] {
        guard !definition.coordinateRules.isEmpty else { return [] }
        return definition.coordinateRules.compactMap { rule in
            guard let block = blocks.first(where: { rule.region.contains(centerOf: $0) }) else { return nil }
            guard let value = coordinateValue(from: block.text, for: rule, documentType: match.documentType) else {
                return nil
            }
            guard isValidTemplateValue(profileKey: rule.profileKey, value: value, documentType: match.documentType) else {
                return nil
            }
            return OcrFieldSuggestion(
                profileKey: rule.profileKey,
                label: rule.label,
                value: value,
                confidence: "High",
                confidenceScore: max(0.9, match.confidence),
                mappingSource: .template
            )
        }
    }

    private static func allPairs(from layout: LayoutIntelligenceAgent.LayoutDocument) -> [OcrLayoutSerializer.LabelValuePair] {
        var pairs = layout.labelValuePairs
        for line in layout.layoutText.components(separatedBy: .newlines) {
            guard let inline = OcrLayoutSerializer.inlineLabelValue(from: line) else { continue }
            pairs.append(inline)
        }
        return pairs
    }

    private static func dedupe(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for suggestion in suggestions {
            if let existing = byKey[suggestion.profileKey],
               existing.confidenceScore >= suggestion.confidenceScore
            {
                continue
            }
            byKey[suggestion.profileKey] = suggestion
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    private static func coordinateValue(
        from text: String,
        for rule: CoordinateRule,
        documentType: String
    ) -> String? {
        if let pair = OcrLayoutSerializer.inlineLabelValue(from: text) {
            let resolved = SemanticFieldLabelMapper.resolve(label: pair.label, documentTypeHint: documentType)
            guard resolved?.profileKey == rule.profileKey else { return nil }
            return pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.contains(":") {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidTemplateValue(profileKey: String, value: String, documentType: String) -> Bool {
        let presentation = DocumentTypePresentation.resolve(documentType)
        let suggestion = OcrFieldSuggestion(
            profileKey: profileKey,
            label: ProfileSchema.definition(for: profileKey)?.label ?? ProfileSchema.label(forExtensionKey: profileKey),
            value: value,
            confidence: "High",
            confidenceScore: 0.9,
            mappingSource: .template
        )
        return ScanFieldValidator.isValid(suggestion, documentType: presentation.enumType)
    }
}
