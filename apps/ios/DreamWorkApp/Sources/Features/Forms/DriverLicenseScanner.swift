import Foundation
import SwiftUI
import Vision
import VisionKit
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

struct DriverLicenseScanResult: Sendable {
    var fullName: String?
    var firstName: String?
    var lastName: String?
    var dateOfBirth: Date?
    var documentNumber: String?
    var addressLine1: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var rawText: String
}

@MainActor
private enum DriverLicenseScannerPipeline {
    static func scan(images: [CGImage]) async throws -> DriverLicenseScanResult {
        // Prefer PDF417 (AAMVA) barcode payload when available; it is much more reliable than OCR.
        guard let firstImage = images.first else {
            throw NSError(domain: "DriverLicenseScanner", code: 11, userInfo: [NSLocalizedDescriptionKey: "No images to scan"])
        }
        let barcodePayloads = (try? Barcode.detectPayloads(in: firstImage)) ?? []
        let barcodeParsed: DriverLicenseScanResult? = barcodePayloads
            .compactMap { DriverLicenseParser.parseAAMVAPDF417($0) }
            .first

        let rawText = try await OCR.recognizeText(from: images)
        let ocrParsed = DriverLicenseParser.parse(rawText)

        if let barcodeParsed {
            var merged = DriverLicenseParser.merge(primary: barcodeParsed, fallback: ocrParsed)
            if !barcodePayloads.isEmpty {
                merged.rawText = "BARCODE:\n\(barcodePayloads.joined(separator: "\n---\n"))\n\nOCR:\n\(rawText)"
            }
            return merged
        }

        return ocrParsed
    }

    static func scan(imageData: Data) async throws -> DriverLicenseScanResult {
        guard let uiImage = UIImage(data: imageData) else {
            throw NSError(domain: "DriverLicenseScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to read image"])
        }
        guard let cg = makeCGImage(from: uiImage) else {
            throw NSError(domain: "DriverLicenseScanner", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unable to decode image for OCR"])
        }
        return try await scan(images: [cg])
    }

    static func scan(fileURL url: URL) async throws -> DriverLicenseScanResult {
        let images = try loadImagesForOCR(from: url)
        if images.isEmpty {
            throw NSError(domain: "DriverLicenseScanner", code: 8, userInfo: [NSLocalizedDescriptionKey: "PDF had no readable pages"])
        }
        return try await scan(images: images)
    }

    static func scan(remoteURL url: URL) async throws -> DriverLicenseScanResult {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "DriverLicenseScanner", code: 4, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
        }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(data: data) else {
                throw NSError(domain: "DriverLicenseScanner", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to read PDF"])
            }
            let images = renderPDF(doc)
            if images.isEmpty {
                throw NSError(domain: "DriverLicenseScanner", code: 8, userInfo: [NSLocalizedDescriptionKey: "PDF had no readable pages"])
            }
            return try await scan(images: images)
        }

        return try await scan(imageData: data)
    }

    private static func loadImagesForOCR(from url: URL) throws -> [CGImage] {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw NSError(domain: "DriverLicenseScanner", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to read PDF"])
            }

            return renderPDF(doc)
        }

        let data = try Data(contentsOf: url)
        guard let uiImage = UIImage(data: data), let cg = makeCGImage(from: uiImage) else {
            throw NSError(domain: "DriverLicenseScanner", code: 9, userInfo: [NSLocalizedDescriptionKey: "Selected file is not a readable image"])
        }
        return [cg]
    }

    private static func makeCGImage(from uiImage: UIImage) -> CGImage? {
        if let cg = uiImage.cgImage { return cg }
        if let ci = uiImage.ciImage {
            let ctx = CIContext(options: nil)
            return ctx.createCGImage(ci, from: ci.extent)
        }
        // Last resort: render into a bitmap context.
        let size = uiImage.size
        if size.width <= 0 || size.height <= 0 { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            uiImage.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    private static func renderPDF(_ doc: PDFDocument) -> [CGImage] {
        var images: [CGImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let cg = renderPDFPage(page) { images.append(cg) }
        }
        if images.isEmpty {
            // throw via caller
            return []
        }
        return images
    }

    private static func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        return image.cgImage
    }
}

@MainActor
struct DriverLicenseScannerView: UIViewControllerRepresentable {
    let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if VNDocumentCameraViewController.isSupported {
            let vc = VNDocumentCameraViewController()
            vc.delegate = context.coordinator
            return vc
        }

        // Fallback for Simulator: allow selecting an image and running on-device OCR.
        let fallback = UIHostingController(rootView: ScannerFallbackView(onResult: onResult))
        return fallback
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

        init(onResult: @escaping (Result<DriverLicenseScanResult, Error>) -> Void) {
            self.onResult = onResult
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) {
                self.onResult(.failure(error))
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images: [CGImage] = (0..<scan.pageCount).compactMap { idx in
                scan.imageOfPage(at: idx).cgImage
            }

            controller.dismiss(animated: true) {
                Task {
                    do {
                        let parsed = try await DriverLicenseScannerPipeline.scan(images: images)
                        self.onResult(.success(parsed))
                    } catch {
                        self.onResult(.failure(error))
                    }
                }
            }
        }
    }
}

private struct ScannerFallbackView: View {
    let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var urlString: String = ""
    @State private var isPresentingFilePicker = false
    @State private var isPresentingDownloadsBrowser = false
    @State private var downloadsBaseURLString: String = "http://127.0.0.1:8009/"
    @State private var downloadsFiles: [URL] = []
    @State private var downloadsError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan Document")
                    .font(.title2)

                Text("On Simulator, use one of the import options below. From a laptop you can either (1) add an image to Photos, (2) drag a file into Files, or (3) serve it over a local URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    HStack {
                        Text("Choose Photo")
                        Spacer()
                        Image(systemName: "photo")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Button {
                    isPresentingFilePicker = true
                } label: {
                    HStack {
                        Text("Choose File (Files)")
                        Spacer()
                        Image(systemName: "doc")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
                .fileImporter(
                    isPresented: $isPresentingFilePicker,
                    allowedContentTypes: [
                        UTType.image,
                        UTType.pdf,
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    Task {
                        await handleFileImportResult(result)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Load from laptop URL")
                        .font(.headline)

                    TextField("http://127.0.0.1:8000/your-id.jpg", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button(isWorking ? "Loading…" : "Load URL and OCR") {
                        Task {
                            await loadFromURL()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Browse Mac Downloads (localhost)")
                        .font(.headline)

                    TextField("http://127.0.0.1:8009/", text: $downloadsBaseURLString)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button(isWorking ? "Loading…" : "Browse Downloads") {
                        Task {
                            await loadDownloadsListing()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)

                    Text("Tip: run `./scripts/serve_downloads.sh` on your Mac first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .sheet(isPresented: $isPresentingDownloadsBrowser) {
                    NavigationStack {
                        List {
                            if let downloadsError {
                                Text(downloadsError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Section("Files") {
                                ForEach(downloadsFiles, id: \.absoluteString) { url in
                                    Button(url.lastPathComponent) {
                                        urlString = url.absoluteString
                                        isPresentingDownloadsBrowser = false
                                        Task { await loadFromURL() }
                                    }
                                }
                            }
                        }
                        .navigationTitle("Downloads")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { isPresentingDownloadsBrowser = false }
                            }
                        }
                    }
                }

                Button("Simulate Scan (Demo Text)") {
                    let parsed = DriverLicenseParser.parse(DriverLicenseParser.demoDriverLicenseText)
                    onResult(.success(parsed))
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                if isWorking {
                    ProgressView("Reading…")
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        guard let data = try await newValue.loadTransferable(type: Data.self) else {
                            throw NSError(domain: "DriverLicenseScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to read image"])
                        }
                        let parsed = try await DriverLicenseScannerPipeline.scan(imageData: data)
                        onResult(.success(parsed))
                    } catch {
                        onResult(.failure(error))
                    }
                }
            }
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let urls = try result.get()
            guard let url = urls.first else {
                throw NSError(domain: "DriverLicenseScanner", code: 6, userInfo: [NSLocalizedDescriptionKey: "No file selected"])
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            let parsed = try await DriverLicenseScannerPipeline.scan(fileURL: url)
            onResult(.success(parsed))
        } catch {
            onResult(.failure(error))
        }
    }

    private func loadFromURL() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            onResult(.failure(NSError(domain: "DriverLicenseScanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let parsed = try await DriverLicenseScannerPipeline.scan(remoteURL: url)
            onResult(.success(parsed))
        } catch {
            onResult(.failure(error))
        }
    }

    private func loadDownloadsListing() async {
        let trimmed = downloadsBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmed), baseURL.scheme != nil else {
            downloadsError = "Invalid base URL"
            downloadsFiles = []
            isPresentingDownloadsBrowser = true
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                throw NSError(domain: "DriverLicenseScanner", code: 10, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
            }

            let html = String(data: data, encoding: .utf8) ?? ""
            let urls = parsePythonHTTPServerListing(html: html, baseURL: baseURL)
            downloadsFiles = urls
            downloadsError = urls.isEmpty ? "No .png/.jpg/.jpeg/.pdf found on server." : nil
            isPresentingDownloadsBrowser = true
        } catch {
            downloadsError = "Failed to load: \(error.localizedDescription)"
            downloadsFiles = []
            isPresentingDownloadsBrowser = true
        }
    }

    private func parsePythonHTTPServerListing(html: String, baseURL: URL) -> [URL] {
        // Parse href="..." from python http.server directory listing.
        // Keep only common document/image types.
        let pattern = #"href="([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var urls: [URL] = []

        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let href = ns.substring(with: m.range(at: 1))
            if href.hasPrefix("?") || href.hasPrefix("#") { continue }
            if href.hasSuffix("/") { continue }
            if href == "../" { continue }

            let decoded = href.removingPercentEncoding ?? href
            let ext = (decoded as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "pdf"].contains(ext) else { continue }
            if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                urls.append(url)
            }
        }

        // Deduplicate + stable sort.
        let unique = Array(Set(urls)).sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        return unique
    }
}

enum OCR {
    static func recognizeText(from images: [CGImage]) async throws -> String {
        var all: [String] = []

        for image in images {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            all.append(lines.joined(separator: "\n"))
        }

        return all.joined(separator: "\n\n")
    }
}

enum Barcode {
    static func detectPayloads(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [
            .PDF417,
            .qr,
            .aztec,
            .code128,
            .dataMatrix,
        ]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let payloads = (request.results ?? [])
            .compactMap { $0.payloadStringValue }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return payloads
    }
}

enum DriverLicenseParser {
    // Heuristic-only parsing. This stays on device; no network calls.
    static func parse(_ text: String) -> DriverLicenseScanResult {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = normalized.joined(separator: "\n")

        var result = DriverLicenseScanResult(rawText: joined)

        // DOB patterns: 04/25/2001, 04-25-2001, 2001-04-25
        result.dateOfBirth = firstDate(in: joined)

        // Look for "DOB" / "Birth" lines.
        if result.dateOfBirth == nil {
            if let dobLine = normalized.first(where: { $0.lowercased().contains("dob") || $0.lowercased().contains("birth") }),
               let d = firstDate(in: dobLine) {
                result.dateOfBirth = d
            }
        }

        // Name heuristics: lines after "Name" or common DL patterns.
        if let nameLine = normalized.first(where: { $0.lowercased().hasPrefix("name") }) {
            result.fullName = nameLine
                .replacingOccurrences(of: "Name", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback: pick the first line that looks like a person name (letters/spaces, 2+ words)
            result.fullName = normalized.first(where: looksLikeName)
        }

        if let full = result.fullName {
            let split = splitName(full)
            result.firstName = split.first
            result.lastName = split.last
        }

        // Address heuristics: find a line containing a street number.
        if let addrIdx = normalized.firstIndex(where: looksLikeStreetAddress) {
            result.addressLine1 = normalized[addrIdx]

            // Try city/state/zip on next line or same line
            let next = addrIdx + 1 < normalized.count ? normalized[addrIdx + 1] : nil
            if let next, let csz = parseCityStateZip(next) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            } else if let csz = parseCityStateZip(normalized[addrIdx]) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            }
        } else {
            // Try to parse any city/state/zip line
            if let line = normalized.first(where: { parseCityStateZip($0) != nil }), let csz = parseCityStateZip(line) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            }
        }

        return result
    }

    static func merge(primary: DriverLicenseScanResult, fallback: DriverLicenseScanResult) -> DriverLicenseScanResult {
        var out = primary
        if out.fullName == nil { out.fullName = fallback.fullName }
        if out.firstName == nil { out.firstName = fallback.firstName }
        if out.lastName == nil { out.lastName = fallback.lastName }
        if out.dateOfBirth == nil { out.dateOfBirth = fallback.dateOfBirth }
        if out.documentNumber == nil { out.documentNumber = fallback.documentNumber }
        if out.addressLine1 == nil { out.addressLine1 = fallback.addressLine1 }
        if out.city == nil { out.city = fallback.city }
        if out.state == nil { out.state = fallback.state }
        if out.postalCode == nil { out.postalCode = fallback.postalCode }
        if out.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.rawText = fallback.rawText
        }
        return out
    }

    static func parseAAMVAPDF417(_ payload: String) -> DriverLicenseScanResult? {
        // AAMVA DL/ID PDF417 payload usually contains ANSI header then lines with data element IDs.
        // We parse common fields:
        // DCS last name, DAC first name, DAD middle, DBB DOB (YYYYMMDD), DAQ document number, DAG address, DAI city, DAJ state, DAK zip.
        let text = payload.replacingOccurrences(of: "\r", with: "\n")
        var lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        if lines.isEmpty {
            lines = text.components(separatedBy: "\n")
        }

        func value(for key: String) -> String? {
            for l in lines {
                if l.hasPrefix(key) {
                    let v = String(l.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        let last = value(for: "DCS")
        let first = value(for: "DAC")
        let middle = value(for: "DAD")
        let dobRaw = value(for: "DBB")
        let docNumber = value(for: "DAQ")
        let addr1 = value(for: "DAG")
        let city = value(for: "DAI")
        let state = value(for: "DAJ")
        let zip = value(for: "DAK")

        if last == nil, first == nil, dobRaw == nil, addr1 == nil, docNumber == nil {
            return nil
        }

        var out = DriverLicenseScanResult(rawText: payload)
        out.firstName = first
        out.lastName = last
        out.documentNumber = docNumber
        if let first, let last {
            out.fullName = [first, middle, last].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        } else if let last, let first {
            out.fullName = "\(first) \(last)"
        }

        if let dobRaw {
            out.dateOfBirth = parseAAMVADateYYYYMMDD(dobRaw)
        }

        out.addressLine1 = addr1
        out.city = city
        out.state = state
        if let zip {
            out.postalCode = zip.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func parseAAMVADateYYYYMMDD(_ s: String) -> Date? {
        let digits = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 8 else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd"
        return df.date(from: digits)
    }

    private static func splitName(_ fullName: String) -> (first: String?, last: String?) {
        let cleaned = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return (nil, nil) }

        if cleaned.contains(",") {
            // LAST, FIRST MIDDLE
            let parts = cleaned.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let last = parts.first
            let rest = parts.count > 1 ? parts[1] : ""
            let first = rest.split(separator: " ").first.map(String.init)
            return (first: first, last: last.map { String($0) })
        }

        let parts = cleaned.split(separator: " ")
        guard parts.count >= 2 else { return (first: cleaned, last: nil) }
        let last = String(parts.last!)
        let first = parts.dropLast().joined(separator: " ")
        return (first: String(first), last: last)
    }

    private static func looksLikeName(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard words.count >= 2 else { return false }
        guard line.range(of: #"^[A-Za-z][A-Za-z\-\.\s]+$"#, options: .regularExpression) != nil else { return false }
        return true
    }

    private static func looksLikeStreetAddress(_ line: String) -> Bool {
        // Simple: starts with digits and has a street-like word.
        guard line.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil else { return false }
        return true
    }

    private static func firstDate(in s: String) -> Date? {
        let patterns = [
            #"(\d{1,2})/(\d{1,2})/(\d{4})"#,
            #"(\d{1,2})-(\d{1,2})-(\d{4})"#,
            #"(\d{4})-(\d{1,2})-(\d{1,2})"#,
        ]
        for p in patterns {
            if let match = s.range(of: p, options: .regularExpression) {
                let str = String(s[match])
                if let d = parseDate(str) { return d }
            }
        }
        return nil
    }

    private static func parseDate(_ str: String) -> Date? {
        let fmts = ["MM/dd/yyyy", "M/d/yyyy", "MM-d-yyyy", "M-d-yyyy", "yyyy-MM-dd", "yyyy-M-d"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: str) { return d }
        }
        return nil
    }

    private struct CityStateZip { let city: String; let state: String; let zip: String }

    private static func parseCityStateZip(_ line: String) -> CityStateZip? {
        // Example: Austin, TX 78701
        // Example: Austin TX 78701
        let cleaned = line.replacingOccurrences(of: ",", with: " ")
        let pattern = #"^(.+?)\s+([A-Z]{2})\s+(\d{5})(?:-\d{4})?$"#
        guard let r = cleaned.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(cleaned[r])
        // Split by spaces from end
        let parts = match.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let zip = String(parts.last!)
        let state = String(parts[parts.count - 2])
        let city = parts.dropLast(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return CityStateZip(city: city, state: state, zip: zip)
    }

    static let demoDriverLicenseText = """
    DRIVER LICENSE
    Name: DOE, JANE
    DOB 04/25/1990
    2457 MEADOWBROOK AVE
    AUSTIN TX 78701
    """
}

