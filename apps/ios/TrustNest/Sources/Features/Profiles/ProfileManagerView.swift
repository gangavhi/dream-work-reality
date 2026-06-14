import SwiftUI

/// Triggered by tapping the ADD node on the TrustNest Wheel.
struct ProfileManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationshipType: RelationshipType = .primary

    private var availableRelationships: [RelationshipType] {
        let hasPrimary = appState.profileManager.profiles.contains { $0.relationshipType == .primary }
        return hasPrimary ? RelationshipType.allCases.filter { $0 != .primary } : RelationshipType.allCases
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Household Member") {
                    TextField("Full name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Relationship", selection: $relationshipType) {
                        ForEach(availableRelationships, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

                if let error = appState.profileManager.lastError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("ProfileManager")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        appState.profileManager.createProfile(name: name, relationshipType: relationshipType)
                        if appState.profileManager.lastError == nil {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                relationshipType = availableRelationships.first ?? .primary
            }
        }
    }
}
