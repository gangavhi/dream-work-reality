import Foundation
import Vision
import UIKit

enum OCRService {
    /// On-device OCR via Apple Vision — no data leaves the device.
    static func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw DocumentProcessingError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum DocumentProcessingError: LocalizedError {
    case invalidImage
    case emptyText
    case databaseFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not read the scanned image."
        case .emptyText: return "No text was detected in the document."
        case .databaseFailure(let message): return message
        }
    }
}
