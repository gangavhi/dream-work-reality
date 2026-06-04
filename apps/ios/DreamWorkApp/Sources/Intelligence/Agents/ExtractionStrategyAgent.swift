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
        let route: DocumentExtractionRouter.Route
        let routeSignals: [String]
        let signals: [String]
    }

    static func determine(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        classification: ClassificationAgent.Result,
        payloadHints: EmbeddedPayloadHints.Result,
        templateMatch: DocumentTemplateAgent.Match?
    ) -> Result {
        var signals: [String] = []
        let routing = DocumentExtractionRouter.decide(
            classification: classification,
            payloadHints: payloadHints,
            layout: layout
        )

        if let templateMatch {
            signals.append("template:\(templateMatch.templateID)")
            return Result(
                structure: .structured,
                route: .knownFastPath,
                routeSignals: routing.signals,
                signals: signals
            )
        }

        if !layout.labelValuePairs.isEmpty {
            signals.append("label_pairs:\(layout.labelValuePairs.count)")
        }
        if classification.openDocumentType != nil {
            signals.append("classified:\(classification.openDocumentType ?? "unknown")")
        }

        let structure: ExtractionDocumentStructure = {
            switch routing.route {
            case .knownFastPath:
                if layout.labelValuePairs.count >= 2 || routing.signals.contains(where: { $0.hasPrefix("signal:known_type") }) {
                    return layout.labelValuePairs.count >= 2 ? .semiStructured : .structured
                }
                return .structured
            case .unknownSemantic:
                return .layoutAI
            }
        }()

        if structure == .layoutAI {
            signals.append("chunked_layout_reasoning")
        }

        return Result(
            structure: structure,
            route: routing.route,
            routeSignals: routing.signals,
            signals: signals
        )
    }
}
