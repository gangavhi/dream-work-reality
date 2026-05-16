import SwiftUI

struct SettingsView: View {
    @State private var devAPIKey: String = DevAPIKeyStore.openAIAPIKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("TrustNest keeps profiles on this device. Add an OpenAI API key here so driver's license scans map name, address, DL number, and dates correctly (calls OpenAI directly from the app).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Development (Stage 1 AI)") {
                    SecureField("OpenAI API key", text: $devAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button("Save API key") {
                        DevAPIKeyStore.saveOpenAIAPIKey(devAPIKey)
                    }

                    if devAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Without a key, scan review uses on-device heuristics only. Person matching and storage routing still work offline via the embedded Rust core.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
