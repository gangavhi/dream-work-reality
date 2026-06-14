import SwiftUI
import PhotosUI

struct ProfileDetailView: View {
    let profile: Profile
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var statusMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    LabeledContent("Name", value: profile.name)
                    LabeledContent("Relationship", value: profile.relationshipType.rawValue)
                    LabeledContent("Individual ID", value: profile.individualId)
                    LabeledContent("Household ID", value: profile.householdId)
                }

                Section("Contextual Capture") {
                    Text("Scans for \(profile.name) are automatically tagged with this individual_id.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Scan Document for \(profile.name)", systemImage: "doc.viewfinder")
                    }
                    .disabled(isProcessing)

                    if isProcessing {
                        ProgressView("Processing on-device…")
                    }
                    if let statusMessage {
                        Text(statusMessage).font(.footnote)
                    }
                }
            }
            .navigationTitle(profile.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await ingestPhoto(newItem) }
            }
            .onAppear {
                appState.activateProfile(profile)
            }
        }
    }

    private func ingestPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        statusMessage = nil
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                statusMessage = "Could not load image."
                return
            }

            let docs = try await DocumentProcessor.processDocument(
                image: image,
                individualId: profile.individualId,
                householdId: profile.householdId,
                documentType: "household_document",
                database: appState.database
            )
            statusMessage = "Document added for \(profile.name) (\(profile.relationshipType.rawValue)). Indexed \(docs.count) chunk(s)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
