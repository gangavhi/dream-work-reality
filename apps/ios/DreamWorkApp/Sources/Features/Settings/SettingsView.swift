import SwiftUI

struct SettingsView: View {
    @State private var devAPIKey: String = DevAPIKeyStore.openAIAPIKey ?? ""
    @State private var llmProvider: GenAISettings.Provider = GenAISettings.provider
    @State private var llmBaseURL: String = GenAISettings.baseURL
    @State private var llmModel: String = GenAISettings.model
    @State private var auditEntries: [IngestAuditEntry] = IngestAuditLog.load()
    @State private var settingsError: String?
    #if DEBUG
    @State private var cloudLLMDevEnabled: Bool = ZeroEgressPolicy.isCloudLLMDevEnabled
    @State private var coreAPISyncEnabled: Bool = ZeroEgressPolicy.isDeveloperCoreAPISyncEnabled
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your data stays on this device. TrustNest does not send document images, OCR text, or profile fields over the internet to fulfill product features.")
                        .appHelperText()
                } header: {
                    Text("Zero egress")
                }

                Section("Document AI provider") {
                    Picker("Provider", selection: $llmProvider) {
                        ForEach(GenAISettings.Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if llmProvider == .onDevice {
                        Text(BundledModelStore.installStatusMessage())
                            .appHelperText()
                    }

                    if llmProvider == .localLLM {
                        TextField("API base URL", text: $llmBaseURL)
                            .fieldInputStyle()
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        TextField("Model name", text: $llmModel)
                            .fieldInputStyle()
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    #if DEBUG
                    if llmProvider == .cloudLLMDevOnly {
                        TextField("API base URL", text: $llmBaseURL)
                            .fieldInputStyle()
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        TextField("Model name", text: $llmModel)
                            .fieldInputStyle()
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        Toggle("Allow cloud LLM (data leaves device)", isOn: $cloudLLMDevEnabled)

                        SecureField("OpenAI API key", text: $devAPIKey)
                            .fieldInputStyle()
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        Text("DEBUG builds only. OCR text is sent to the configured cloud endpoint. Disabled in TestFlight and App Store releases.")
                            .appHelperText()
                            .foregroundStyle(.orange)
                    }

                    Toggle("Sync to localhost core-api (extension demo)", isOn: $coreAPISyncEnabled)
                    Text("When enabled, profile changes sync to http://127.0.0.1:18081 for the Chrome extension demo. Disabled in Release builds.")
                        .appHelperText()
                    #endif

                    Button("Save AI settings") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)

                    if let settingsError {
                        Text(settingsError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if llmProvider == .localLLM {
                        Text("Run Ollama or LM Studio on your Mac or PC on the same Wi‑Fi network. Use your machine's local IP (e.g. 192.168.x.x) — not a public internet URL.")
                            .appHelperText()
                    } else if llmProvider == .off {
                        Text("Scans use on-device OCR, barcode parsing, and heuristics. Person matching and storage routing remain offline via the embedded Rust core.")
                            .appHelperText()
                    }
                }

                Section("Ingest audit log") {
                    if auditEntries.isEmpty {
                        Text("Applied document scans will appear here for traceability.")
                            .appHelperText()
                    } else {
                        ForEach(auditEntries.prefix(20)) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.documentType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let name = entry.personName, !name.isEmpty {
                                    Text(name)
                                        .fieldValueStyle()
                                }
                                Text("\(entry.fieldCount) field\(entry.fieldCount == 1 ? "" : "s") saved")
                                    .appHelperText()
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                if !entry.notes.isEmpty {
                                    Text(entry.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button("Refresh audit log") {
                        auditEntries = IngestAuditLog.load()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveSettings() {
        settingsError = nil

        if llmProvider == .localLLM || llmProvider == .cloudLLMDevOnly {
            let url = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else {
                settingsError = "Enter a base URL for the LLM endpoint."
                return
            }
            guard ZeroEgressPolicy.allowsLLMEndpoint(url) else {
                settingsError = "That URL is not allowed. Use localhost, a private LAN IP (192.168.x.x), or a .local hostname. Public internet endpoints are blocked in this build."
                return
            }
        }

        #if DEBUG
        ZeroEgressPolicy.setCloudLLMDevEnabled(cloudLLMDevEnabled)
        ZeroEgressPolicy.setDeveloperCoreAPISyncEnabled(coreAPISyncEnabled)
        if llmProvider == .cloudLLMDevOnly, !cloudLLMDevEnabled {
            llmProvider = .off
        }
        DevAPIKeyStore.saveOpenAIAPIKey(devAPIKey)
        #endif

        GenAISettings.provider = llmProvider
        GenAISettings.baseURL = llmBaseURL
        GenAISettings.model = llmModel
    }
}
