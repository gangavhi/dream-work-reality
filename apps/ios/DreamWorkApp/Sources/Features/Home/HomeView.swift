import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showDocumentImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Home Screen")
                    .font(.title2)
                    .accessibilityIdentifier("homeScreenTitle")

                Text(appState.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeStatusText")

                Text("Manual entries: \(appState.manualEntryCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeManualEntryCount")

                Text("OCR extraction runs (SQLite): \(appState.extractionRunCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeExtractionRunCount")

                if appState.isImportingDocument {
                    ProgressView("Extracting text…")
                        .accessibilityIdentifier("homeImportProgress")
                }

                Button("Refresh Core Status") {
                    appState.refreshStatus()
                }
                .buttonStyle(.borderedProminent)

                Button("Upload document (PDF or image)") {
                    showDocumentImporter = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isImportingDocument)
                .accessibilityIdentifier("homeUploadDocumentButton")

                Button("Save + Load Demo Person") {
                    appState.saveAndLoadDemoPerson()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("saveLoadPersonButton")
            }
            .padding()
            .navigationTitle("Home")
            .fileImporter(
                isPresented: $showDocumentImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await appState.importDocument(from: url)
                    }
                case .failure(let error):
                    appState.documentImportMessage = error.localizedDescription
                }
            }
            .alert(
                "Document import",
                isPresented: Binding(
                    get: { appState.documentImportMessage != nil },
                    set: { if !$0 { appState.documentImportMessage = nil } }
                )
            ) {
                Button("OK") {
                    appState.documentImportMessage = nil
                }
            } message: {
                Text(appState.documentImportMessage ?? "")
            }
            .onAppear {
                appState.refreshStatus()
            }
        }
    }
}
