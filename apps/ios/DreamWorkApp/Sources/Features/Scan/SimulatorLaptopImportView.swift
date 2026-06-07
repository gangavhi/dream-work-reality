import SwiftUI

#if targetEnvironment(simulator)
/// Browse PDFs and images served from the Mac (project samples + Downloads) and import into the ingest pipeline.
struct SimulatorLaptopImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var sampleDocs: [LaptopDocumentListing.RemoteDocument] = []
    @State private var downloadDocs: [LaptopDocumentListing.RemoteDocument] = []
    @State private var sampleError: String?
    @State private var downloadsError: String?
    @State private var isLoading = false
    @State private var importingName: String?
    @State private var macHost = LaptopDocumentListing.macHost
    @State private var importError: String?
    @State private var showFinderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap any file below to run OCR. Files come from your Mac Downloads folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showFinderPicker = true
                    } label: {
                        Label("Pick a different folder in Finder…", systemImage: "folder")
                    }
                    .disabled(importingName != nil)
                    if isLoading {
                        Label("Loading Mac Downloads…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if downloadsError != nil {
                        Label("Mac Downloads server not running", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                sourceSection(
                    title: "Mac Downloads",
                    subtitle: "Files in ~/Downloads on your MacBook",
                    documents: downloadDocs,
                    error: downloadsError,
                    serverHint: "./scripts/prepare_simulator_testing.sh --servers-only"
                )

                sourceSection(
                    title: "Project samples (optional)",
                    subtitle: "demo/sample-documents/",
                    documents: sampleDocs,
                    error: sampleError,
                    serverHint: LaptopDocumentListing.Source.sampleDocuments.setupHint
                )

                Section("If the list is empty") {
                    Text("In Terminal on your Mac, run:")
                        .font(.caption)
                    Text("./scripts/prepare_simulator_testing.sh --servers-only")
                        .font(.caption.monospaced())
                    Text("Then tap Refresh. Or drag a PDF from Finder onto the Simulator window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Mac host", text: $macHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { LaptopDocumentListing.macHost = macHost }
                }
            }
            .navigationTitle("Mac Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        LaptopDocumentListing.macHost = macHost
                        importError = nil
                        Task { await reloadAll() }
                    }
                    .disabled(isLoading || importingName != nil)
                }
            }
            .overlay {
                if isLoading || importingName != nil {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(importingName.map { "Importing \($0)…" } ?? "Loading Mac folders…")
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .task {
                await reloadAll()
            }
            .sheet(isPresented: $showFinderPicker) {
                SimulatorMacFilePicker { url in
                    Task { await importLocalFile(url) }
                }
            }
        }
    }

    private func importLocalFile(_ url: URL) async {
        importingName = url.lastPathComponent
        importError = nil
        defer { importingName = nil }
        do {
            let localURL = try DocumentImportHelper.makeLocalCopy(of: url)
            appState.documentImportMessage = nil
            await appState.importDocument(from: localURL, urlIsTemporaryCopy: true)
            if appState.scanReviewPayload != nil {
                dismiss()
            } else if let message = appState.documentImportMessage {
                importError = message
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        subtitle: String,
        documents: [LaptopDocumentListing.RemoteDocument],
        error: String?,
        serverHint: String
    ) -> some View {
        Section {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Run: \(serverHint)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if documents.isEmpty {
                Text("No documents found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(documents) { doc in
                    Button {
                        Task { await importDocument(doc) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doc.displayName)
                                .font(.body)
                            Text(doc.sourceLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(importingName != nil)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(subtitle)
        }
    }

    private func reloadAll() async {
        isLoading = true
        defer { isLoading = false }
        LaptopDocumentListing.macHost = macHost

        async let samples = LaptopDocumentListing.load(from: .sampleDocuments)
        async let downloads = LaptopDocumentListing.load(from: .macDownloads)
        let sampleResult = await samples
        let downloadResult = await downloads

        sampleDocs = sampleResult.documents
        sampleError = sampleResult.errorMessage
        downloadDocs = downloadResult.documents
        downloadsError = downloadResult.errorMessage
    }

    private func importDocument(_ doc: LaptopDocumentListing.RemoteDocument) async {
        importingName = doc.displayName
        importError = nil
        defer { importingName = nil }
        appState.documentImportMessage = nil
        await appState.importDocument(fromRemoteURL: doc.url)
        if appState.scanReviewPayload != nil {
            dismiss()
        } else if let message = appState.documentImportMessage {
            importError = message
        } else {
            importError = "Import finished but no scan review opened. Try Refresh and pick the file again."
        }
    }
}
#endif
