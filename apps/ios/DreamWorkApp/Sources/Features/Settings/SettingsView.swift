import SwiftUI

struct SettingsView: View {
    @State private var llmProvider: GenAISettings.Provider = GenAISettings.provider
    @State private var auditEntries: [IngestAuditEntry] = IngestAuditLog.load()
    #if DEBUG
    @State private var coreAPISyncEnabled: Bool = ZeroEgressPolicy.isDeveloperCoreAPISyncEnabled
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your data stays on this device. TrustNest does not send document images, OCR text, or profile fields to remote AI services over the internet.")
                        .appHelperText()
                } header: {
                    Text("Zero egress")
                }

                Section("Document AI") {
                    Picker("Provider", selection: $llmProvider) {
                        ForEach(GenAISettings.Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if llmProvider == .onDevice {
                        Text(BundledModelStore.installStatusMessage())
                            .appHelperText()
                        Text(ModelArtifactRegistry.statusSummary())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Field mapping uses on-device heuristics, layout analysis, and barcode/MRZ parsing. Optional bundled models load when present in the app bundle.")
                            .appHelperText()
                    } else {
                        Text("Scans use on-device OCR, barcode parsing, and heuristics. Person matching and storage routing remain offline via the embedded Rust core.")
                            .appHelperText()
                    }

                    Button("Save AI settings") {
                        GenAISettings.provider = llmProvider
                        #if DEBUG
                        ZeroEgressPolicy.setDeveloperCoreAPISyncEnabled(coreAPISyncEnabled)
                        #endif
                    }
                    .fontWeight(.semibold)

                    #if DEBUG
                    Toggle("Sync to localhost core-api (extension demo)", isOn: $coreAPISyncEnabled)
                    Text("When enabled, profile changes sync to http://127.0.0.1:18081 for the Chrome extension demo. Disabled in Release builds.")
                        .appHelperText()
                    #endif
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
