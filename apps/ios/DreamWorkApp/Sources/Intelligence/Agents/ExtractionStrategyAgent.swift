import Foundation

enum ExtractionDocumentStructure: String, Hashable {
    case structured
    case semiStructured
    case layoutAI
}

/// Chooses extraction mode after OCR and classification.
enum ExtractionStrategyAgent {
    struct Result: Hashable {
        let structure: ExtractionDocumentStructure
        let signals: [String]
    }

    static func determine(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        classification: ClassificationAgent.Result,
        templateMatch: DocumentTemplateAgent.Match?
    ) -> Result {
        var signals: [String] = []

        if let templateMatch {
            signals.append("template:\(templateMatch.templateID)")
            return Result(structure: .structured, signals: signals)
        }

        if !layout.labelValuePairs.isEmpty {
            signals.append("label_pairs:\(layout.labelValuePairs.count)")
        }
        if classification.openDocumentType != nil {
            signals.append("classified:\(classification.openDocumentType ?? "unknown")")
        }

        if layout.labelValuePairs.count >= 2 || classification.openDocumentType != nil {
            return Result(structure: .semiStructured, signals: signals)
        }

        signals.append("chunked_layout_reasoning")
        return Result(structure: .layoutAI, signals: signals)
    }
}
