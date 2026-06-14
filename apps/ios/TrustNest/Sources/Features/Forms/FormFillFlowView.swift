import SwiftUI

struct FormFillFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var detectedFields: [WebFormField] = []
    @State private var showingWebView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let profile = appState.activeProfile {
                    Text("Filling form for \(profile.name) (\(profile.relationshipType.rawValue))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Website form URL", text: $appState.formURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("formURLField")

                Button("Open Form in Browser") {
                    showingWebView = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.formURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.isExtracting {
                    ProgressView("Running ExtractField…")
                }

                if !appState.extractedFields.isEmpty {
                    FormFieldsPanel(fields: appState.extractedFields) { fieldId, newValue in
                        appState.applyManualOverride(fieldId: fieldId, newValue: newValue)
                    }
                }

                if let status = appState.statusMessage {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Website Form Fill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingWebView) {
                WebFormAssistView(
                    urlString: appState.formURLString,
                    extractedFields: appState.extractedFields,
                    onFieldsDetected: { fields in
                        detectedFields = fields
                        appState.extractAllFields(fields)
                    },
                    onApplyValues: { fields in
                        appState.extractedFields = fields
                    }
                )
            }
        }
    }
}
