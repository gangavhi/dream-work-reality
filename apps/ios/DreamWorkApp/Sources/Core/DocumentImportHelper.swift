import Foundation
import UniformTypeIdentifiers

enum DocumentImportHelper {
    enum ImportError: LocalizedError {
        case emptyFile
        case couldNotRead(String)

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The selected file is empty or could not be read. On Simulator, drag the image/PDF onto the Simulator window first, or copy the file into the app via the picker again."
            case .couldNotRead(let detail):
                return "Could not read the file: \(detail)"
            }
        }
    }

    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .image, .jpeg, .png, .heic, .tiff, .gif, .bmp]
        if let webp = UTType(filenameExtension: "webp") {
            types.append(webp)
        }
        return types
    }

    /// Copies a security-scoped / iCloud picker URL into a temp file the app can read during async OCR.
    static func makeLocalCopy(of pickedURL: URL) throws -> URL {
        let accessed = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = pickedURL.pathExtension.isEmpty ? "bin" : pickedURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("trustnest-import-\(UUID().uuidString).\(ext)")

        do {
            if FileManager.default.isReadableFile(atPath: pickedURL.path) {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: pickedURL, to: destination)
            } else {
                let data = try Data(contentsOf: pickedURL)
                guard !data.isEmpty else { throw ImportError.emptyFile }
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            throw ImportError.couldNotRead(error.localizedDescription)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw ImportError.emptyFile }
        return destination
    }
}
