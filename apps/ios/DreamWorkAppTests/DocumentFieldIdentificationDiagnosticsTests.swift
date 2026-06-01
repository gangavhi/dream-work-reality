import XCTest
@testable import DreamWorkApp

final class DocumentFieldIdentificationDiagnosticsTests: XCTestCase {
    func testDiagnosticsForKnownFieldIdentificationFailures() async {
        await runCase(
            name: "insurance_carrier_context",
            expectedType: "insurance_card",
            lines: [
                ("INSURANCE CARD", 0.10, 0.90),
                ("Carrier: Blue Shield", 0.10, 0.80),
                ("Member ID: MEM-12345", 0.10, 0.70),
                ("Group No: GRP-9", 0.10, 0.60),
            ]
        )

        await runCase(
            name: "passport_issue_date_context",
            expectedType: "passport",
            lines: [
                ("PASSPORT", 0.10, 0.90),
                ("Surname: DOE", 0.10, 0.80),
                ("Given Name: JOHN", 0.10, 0.70),
                ("Date of Issue: 01/10/2023", 0.10, 0.60),
                ("Date of Expiry: 01/10/2033", 0.10, 0.50),
            ]
        )

        await runCase(
            name: "driver_license_expiry_context",
            expectedType: "drivers_license",
            lines: [
                ("TEXAS DRIVER LICENSE", 0.10, 0.90),
                ("First Name: Jane", 0.10, 0.80),
                ("Last Name: Smith", 0.10, 0.70),
                ("Date of Expiry: 03/15/2031", 0.10, 0.60),
                ("License No: D12345678", 0.10, 0.50),
            ]
        )

        await runCase(
            name: "visa_classification_gap",
            expectedType: "visa",
            lines: [
                ("VISA", 0.10, 0.90),
                ("Surname: DOE", 0.10, 0.80),
                ("Given Name: JOHN", 0.10, 0.70),
                ("Visa Number: V1234567", 0.10, 0.60),
                ("Nationality: INDIA", 0.10, 0.50),
            ]
        )
    }

    private func runCase(
        name: String,
        expectedType: String,
        lines: [(text: String, x: Float, y: Float)]
    ) async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: lines.map { item in
                VisionOcrAdapter.TextBlock(
                    text: item.text,
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: item.x, y: item.y, width: 0.55, height: 0.05)
                )
            }),
        ])
        let payloadHints = EmbeddedPayloadHints.Result.empty
        let layout = LayoutIntelligenceAgent.analyze(document: doc, payloadHints: payloadHints)
        let machineReadable = MachineReadableFieldExtractor.extract(from: payloadHints, plainOCRText: layout.layoutText)
        let classification = ClassificationAgent.classify(
            modelInput: layout.modelInput,
            mappedDocumentType: nil,
            machineReadableSources: machineReadable.sources
        )
        let template = DocumentTemplateAgent.match(layout: layout, classification: classification)
        let strategy = ExtractionStrategyAgent.determine(
            layout: layout,
            classification: classification,
            payloadHints: payloadHints,
            templateMatch: template
        )
        let result = await DocumentIntelligencePipeline.extract(document: doc)

        print("DIAG|CASE|\(name)")
        print("DIAG|EXPECTED_TYPE|\(expectedType)")
        print("DIAG|CLASSIFICATION|open=\(classification.openDocumentType ?? "nil")|display=\(classification.displayLabel)|enum=\(classification.enumType.rawValue)|confidence=\(classification.confidence)")
        print("DIAG|LABEL_PAIRS|\(layout.labelValuePairs.map { "\($0.label)=\($0.value)" }.joined(separator: " || "))")
        print("DIAG|TEMPLATE|\(template?.templateID ?? "nil")|signals=\(template?.signals.joined(separator: ",") ?? "")")
        print("DIAG|STRATEGY|\(strategy.structure.rawValue)|signals=\(strategy.signals.joined(separator: ","))")
        print("DIAG|TRACE|\(result.pipelineTrace.joined(separator: " > "))")
        print("DIAG|SUGGESTIONS|\(result.suggestions.map { "\($0.profileKey)=\($0.value)[\($0.mappingSource?.rawValue ?? "nil"):\(String(format: "%.2f", $0.confidenceScore))]" }.joined(separator: " || "))")
        print("DIAG|CANONICAL|first=\(result.autofillPayload.canonicalIdentity.person.firstName)|last=\(result.autofillPayload.canonicalIdentity.person.lastName)|passport=\(result.autofillPayload.canonicalIdentity.identity.passportNumber)|dl=\(result.autofillPayload.canonicalIdentity.identity.driverLicenseNumber)")
    }
}
