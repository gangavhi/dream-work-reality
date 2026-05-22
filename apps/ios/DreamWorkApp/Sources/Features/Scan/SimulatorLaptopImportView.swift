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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a file from your Mac to test scan, OCR, and field mapping.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isLoading {
                        Label("Checking Mac folders…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if sampleError != nil && downloadsError != nil {
                        Label("Mac servers not running", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Start servers") {
                        Text("./scripts/prepare_simulator_testing.sh")
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                }

                sourceSection(
                    title: "Project sample documents",
                    subtitle: "demo/sample-documents (Texas DL, etc.)",
                    documents: sampleDocs,
                    error: sampleError,
                    serverHint: LaptopDocumentListing.Source.sampleDocuments.setupHint
                )

                sourceSection(
                    title: "Mac Downloads",
                    subtitle: "~/Downloads",
                    documents: downloadDocs,
                    error: downloadsError,
                    serverHint: LaptopDocumentListing.Source.macDownloads.setupHint
                )

                Section("Other ways to test") {
                    Text("Drag a PDF or image from Finder onto the Simulator window, then use Upload PDF or image → Photos/Files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Copy any test file into demo/sample-documents/ or ~/Downloads/, then tap Refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import from Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
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
        defer { importingName = nil }
        await appState.importDocument(fromRemoteURL: doc.url)
        dismiss()
    }
}
#endif
