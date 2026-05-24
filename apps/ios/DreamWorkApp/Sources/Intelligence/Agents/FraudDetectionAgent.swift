import Foundation

/// Fraud / tamper signals — stub until `fraud.doc.v1` model ships.
enum FraudDetectionAgent {
    struct Finding: Hashable {
        let code: String
        let message: String
        let severity: String
    }

    static func analyze(fileURL: URL?, plainText: String) -> [Finding] {
        guard case .installed = ModelArtifactRegistry.loadState(for: .fraudDetector) else {
            return heuristicMetadataChecks(fileURL: fileURL, plainText: plainText)
        }
        return heuristicMetadataChecks(fileURL: fileURL, plainText: plainText)
    }

    private static func heuristicMetadataChecks(fileURL: URL?, plainText: String) -> [Finding] {
        var findings: [Finding] = []
        if let url = fileURL, url.pathExtension.lowercased() == "pdf" {
            if plainText.count < 24 {
                findings.append(
                    Finding(
                        code: "pdf_low_text",
                        message: "PDF has very little extractable text — may be a scan image or protected file.",
                        severity: "info"
                    )
                )
            }
        }
        return findings
    }
}
