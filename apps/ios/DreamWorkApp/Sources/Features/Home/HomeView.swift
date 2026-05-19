import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

#if targetEnvironment(simulator)
    @State private var showLaptopImport = false
#endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Household profiles, on your device")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Scan an ID or document, review the extracted fields, then copy them into medical, tax, school, or other forms.")
                            .appHelperText()
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                }

                Section {
                    AppStepRow(
                        number: 1,
                        title: "Capture",
                        detail: "Scan with the camera or upload a photo/PDF."
                    )
                    AppStepRow(
                        number: 2,
                        title: "Review",
                        detail: "Check names, dates, and addresses before saving."
                    )
                    AppStepRow(
                        number: 3,
                        title: "Use",
                        detail: "Open Forms to copy values into other apps."
                    )
                } header: {
                    Text("How it works")
                }

                Section {
                    AppActionCard(
                        title: "Scan with camera",
                        subtitle: "Best for driver's licenses, passports, and IDs",
                        systemImage: "camera.viewfinder"
                    ) {
                        appState.showDocumentScanner = true
                    }
                    .disabled(appState.isImportingDocument)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    AppActionCard(
                        title: "Upload PDF or image",
                        subtitle: "Pick from Files, Photos, or email attachments",
                        systemImage: "doc.badge.plus",
                        tint: .blue
                    ) {
                        appState.showFileImporter = true
                    }
                    .disabled(appState.isImportingDocument)
                    .accessibilityIdentifier("homeUploadDocumentButton")
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if appState.isImportingDocument {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading document…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Get started")
                }

#if targetEnvironment(simulator)
                Section {
                    AppActionCard(
                        title: "Browse laptop documents",
                        subtitle: "Test with files from your Mac (Simulator only)",
                        systemImage: "macbook.and.iphone",
                        tint: .purple
                    ) {
                        showLaptopImport = true
                    }
                    .disabled(appState.isImportingDocument)
                    .accessibilityIdentifier("homeBrowseLaptopDocumentsButton")
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Developer testing")
                }
#endif

                if !appState.people.isEmpty {
                    Section {
                        Button {
                            appState.selectedTab = .people
                        } label: {
                            HStack {
                                Label(
                                    "\(appState.people.count) saved profile\(appState.people.count == 1 ? "" : "s")",
                                    systemImage: "person.2.fill"
                                )
                                .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .appListChrome()
            .navigationTitle("Home")
#if targetEnvironment(simulator)
            .sheet(isPresented: $showLaptopImport) {
                SimulatorLaptopImportView()
            }
#endif
            .sheet(isPresented: $appState.showDocumentScanner) {
                DocumentCameraView { url in
                    Task {
                        await appState.importDocument(from: url)
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
                    do {
                        let localURL = try DocumentImportHelper.makeLocalCopy(of: url)
                        Task {
                            await appState.importDocument(
                                from: localURL,
                                urlIsTemporaryCopy: true
                            )
                        }
                    } catch {
                        appState.documentImportMessage = error.localizedDescription
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
                appState.refreshPeopleList()
            }
        }
    }
}
