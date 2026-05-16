import Foundation
import UIKit
import UniformTypeIdentifiers

enum DocumentImportHelper {
    enum ContentKind {
        case pdf
        case raster
    }

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

    /// Classifies a local file for the OCR pipeline (extension and/or magic bytes).
    static func contentKind(for url: URL) -> ContentKind? {
        if isPDF(url) { return .pdf }
        if isRaster(url) { return .raster }
        return nil
    }

    static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        return filePrefix(url, matches: Data("%PDF-".utf8))
    }

    static func isRaster(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let rasterExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp"]
        if rasterExtensions.contains(ext) { return true }
        if UIImage(contentsOfFile: url.path) != nil { return true }
        return filePrefix(url, matches: Data([0xFF, 0xD8, 0xFF])) // JPEG
            || filePrefix(url, matches: Data([0x89, 0x50, 0x4E, 0x47])) // PNG
            || filePrefix(url, matches: Data("GIF8".utf8))
    }

    private static func filePrefix(_ url: URL, matches prefix: Data) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: prefix.count), head.count == prefix.count else {
            return false
        }
        return head == prefix
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
