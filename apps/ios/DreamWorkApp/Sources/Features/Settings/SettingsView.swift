import SwiftUI

struct SettingsView: View {
    @State private var auditEntries: [IngestAuditEntry] = IngestAuditLog.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("On-device only", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("TrustNest rewrite v2 runs entirely on this iPhone or iPad. Vision OCR, barcode/MRZ parsing, and field mapping never call remote AI. Scanned documents are encrypted with AES-GCM and stored in Application Support — nothing leaves your device.")
                        .appHelperText()
                } header: {
                    Text("Privacy & security")
                }

                Section {
                    Text("Extraction uses Apple Vision, on-device parsers, and your household profile. SQLite persistence uses the embedded Rust core.")
                        .appHelperText()
                } header: {
                    Text("How extraction works")
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
