import Foundation

/// Fetches document listings from a Mac-hosted HTTP folder (Simulator uses 127.0.0.1).
enum LaptopDocumentListing {
    struct RemoteDocument: Identifiable, Hashable {
        let url: URL
        let displayName: String
        let sourceLabel: String

        var id: URL { url }
    }

    enum Source: String, CaseIterable, Identifiable {
        case sampleDocuments = "Project samples"
        case macDownloads = "Mac Downloads"

        var id: String { rawValue }

        var baseURL: URL {
            switch self {
            case .sampleDocuments:
                URL(string: "http://127.0.0.1:8010/")!
            case .macDownloads:
                URL(string: "http://127.0.0.1:8009/")!
            }
        }

        var setupHint: String {
            switch self {
            case .sampleDocuments:
                "./scripts/serve_sample_documents.sh"
            case .macDownloads:
                "./scripts/serve_downloads.sh"
            }
        }
    }

    struct LoadResult {
        let documents: [RemoteDocument]
        let errorMessage: String?
    }

    static func load(from source: Source) async -> LoadResult {
        do {
            let (data, response) = try await urlSession.data(from: source.baseURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(status) else {
                throw NSError(domain: "LaptopDocumentListing", code: status, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(status)",
                ])
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            let parsed = parseHTMLListing(html: html, baseURL: source.baseURL, sourceLabel: source.rawValue)
            if parsed.isEmpty {
                return LoadResult(
                    documents: [],
                    errorMessage: """
                    Connected to \(source.baseURL.absoluteString) but no PDF or image files were listed.
                    Add PNG, JPG, or PDF files to the folder, then tap Refresh.
                    """
                )
            }
            return LoadResult(documents: parsed, errorMessage: nil)
        } catch {
            let hint = connectionHint(for: source)
            return LoadResult(
                documents: [],
                errorMessage: """
                Could not reach your Mac at \(source.baseURL.absoluteString).

                \(hint)

                Error: \(error.localizedDescription)
                """
            )
        }
    }

    static func downloadToTemporaryFile(from remoteURL: URL) async throws -> URL {
        let (data, response) = try await urlSession.data(from: remoteURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200 ..< 300).contains(status) else {
            throw NSError(domain: "LaptopDocumentListing", code: status, userInfo: [
                NSLocalizedDescriptionKey: "Download failed (HTTP \(status))",
            ])
        }
        guard !data.isEmpty else {
            throw DocumentImportHelper.ImportError.emptyFile
        }

        let ext = remoteURL.pathExtension.isEmpty ? "bin" : remoteURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("trustnest-laptop-\(UUID().uuidString).\(ext)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func parseHTMLListing(html: String, baseURL: URL, sourceLabel: String) -> [RemoteDocument] {
        let pattern = #"href="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var items: [RemoteDocument] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let href = ns.substring(with: match.range(at: 1))
            if href.hasPrefix("?") || href.hasPrefix("#") || href == "../" { continue }

            let decoded = href.removingPercentEncoding ?? href
            if decoded.hasSuffix("/") { continue }

            let ext = (decoded as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            items.append(RemoteDocument(url: url, displayName: url.lastPathComponent, sourceLabel: sourceLabel))
        }

        return Array(Set(items.map(\.url)))
            .compactMap { url in items.first { $0.url == url } }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "pdf", "heic", "heif", "tif", "tiff", "gif", "webp",
    ]

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private static func connectionHint(for source: Source) -> String {
        switch source {
        case .sampleDocuments:
            return """
            1. In Terminal on your Mac, run:
               ./scripts/prepare_simulator_testing.sh
            2. Or start only sample docs:
               ./scripts/serve_sample_documents.sh
            3. In Simulator (not TestFlight on a phone), tap Refresh here.
            """
        case .macDownloads:
            return """
            1. In Terminal on your Mac, run:
               ./scripts/prepare_simulator_testing.sh
            2. Or start only Downloads:
               ./scripts/serve_downloads.sh
            3. Simulator uses 127.0.0.1; a physical iPhone needs your Mac's Wi‑Fi IP (see script output).
            """
        }
    }
}
