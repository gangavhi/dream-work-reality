import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("TrustNest keeps household profiles on this device. Scan IDs, review extracted fields, then use Forms to copy values into medical, tax, school, or other paperwork.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Vault status") {
                    LabeledContent("Core", value: appState.statusText)
                    LabeledContent("Profiles", value: "\(appState.manualEntryCount)")
                    LabeledContent("OCR runs", value: "\(appState.extractionRunCount)")
                }

                Section {
                    Text("Simulator tip: drag a PDF or image from your Mac onto the Simulator window, then use Upload and pick it from Photos/Files. On a real iPhone, use Scan or Upload normally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Capture document") {
                    Picker("Document type", selection: $appState.pendingScanDocumentType) {
                        ForEach(ScannedDocumentType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }

                    Button {
                        appState.showDocumentScanner = true
                    } label: {
                        Label("Scan with camera", systemImage: "camera.viewfinder")
                    }
                    .disabled(appState.isImportingDocument)

                    Button {
                        appState.showFileImporter = true
                    } label: {
                        Label("Upload PDF or image", systemImage: "doc.badge.plus")
                    }
                    .disabled(appState.isImportingDocument)
                    .accessibilityIdentifier("homeUploadDocumentButton")

                    if appState.isImportingDocument {
                        HStack {
                            ProgressView()
                            Text("Extracting text…")
                        }
                    }
                }

                Section("Quick actions") {
                    Button("Refresh status") {
                        appState.refreshStatus()
                    }

                    Button("Open People") {
                        appState.selectedTab = .people
                    }

                    Button("Open Forms") {
                        appState.selectedTab = .forms
                    }
                }
            }
            .navigationTitle("Home")
            .sheet(isPresented: $appState.showDocumentScanner) {
                DocumentCameraView { url in
                    Task {
                        await appState.importDocument(
                            from: url,
                            documentType: appState.pendingScanDocumentType
                        )
                    }
                }
            }
            .fileImporter(
                isPresented: $appState.showFileImporter,
                allowedContentTypes: DocumentImportHelper.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await appState.importDocument(
                            from: url,
                            documentType: appState.pendingScanDocumentType
                        )
                    }
                case .failure(let error):
                    appState.documentImportMessage = error.localizedDescription
                }
            }
            .sheet(item: $appState.scanReviewPayload) { payload in
                ScanReviewView(payload: payload)
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
                if let message = appState.documentImportMessage {
                    Text(message)
                }
            }
            .onAppear {
                appState.refreshStatus()
            }
        }
    }
}
