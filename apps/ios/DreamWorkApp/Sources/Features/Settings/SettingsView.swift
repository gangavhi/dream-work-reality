import SwiftUI

struct SettingsView: View {
    @State private var devAPIKey: String = DevAPIKeyStore.openAIAPIKey ?? ""
    @State private var llmProvider: GenAISettings.Provider = GenAISettings.provider
    @State private var llmBaseURL: String = GenAISettings.baseURL
    @State private var llmModel: String = GenAISettings.model
    @State private var auditEntries: [IngestAuditEntry] = IngestAuditLog.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("TrustNest uses Apple Vision and NaturalLanguage on-device by default. Optionally enable Ollama or a cloud API for extra field extraction (data may leave the device).")
                        .appHelperText()
                }

                Section("Document AI provider") {
                    Picker("Provider", selection: $llmProvider) {
                        ForEach(GenAISettings.Provider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }

                    if llmProvider == .ollama || llmProvider == .openAI {
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

                    if llmProvider == .openAI {
                        SecureField("OpenAI API key", text: $devAPIKey)
                            .fieldInputStyle()
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    Button("Save AI settings") {
                        GenAISettings.provider = llmProvider
                        GenAISettings.baseURL = llmBaseURL
                        GenAISettings.model = llmModel
                        DevAPIKeyStore.saveOpenAIAPIKey(devAPIKey)
                    }
                    .fontWeight(.semibold)

                    if llmProvider == .ollama {
                        Text("Run Ollama on your Mac (e.g. llama3.2, phi3, mistral). On a physical iPhone, use your Mac's LAN IP instead of 127.0.0.1.")
                            .appHelperText()
                    } else {
                        Text("Scans use Apple Vision OCR, NaturalLanguage, barcode/MRZ parsing, and on-device profile building. SQLite persistence uses the embedded Rust core.")
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
}
