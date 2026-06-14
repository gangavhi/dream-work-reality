import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingProfileManager = false
    @State private var showingFormFill = false
    @State private var selectedProfile: Profile?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.88, green: 0.93, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    header
                    TrustNestWheelView(
                        profiles: appState.profileManager.profiles,
                        activeProfileId: appState.activeProfile?.individualId,
                        onProfileTap: { profile in
                            appState.activateProfile(profile)
                            selectedProfile = profile
                        },
                        onAddTap: {
                            showingProfileManager = true
                        }
                    )
                    .accessibilityIdentifier("trustNestWheel")

                    if appState.profileManager.profiles.isEmpty {
                        Text("Tap ADD to create your household")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let active = appState.activeProfile {
                        activeProfileBanner(active)
                    }

                    Button {
                        showingFormFill = true
                    } label: {
                        Label("Fill Website Form", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.activeProfile == nil)
                    .accessibilityIdentifier("fillWebsiteFormButton")
                }
                .padding()
            }
            .navigationTitle("TrustNest")
            .sheet(isPresented: $showingProfileManager) {
                ProfileManagerView()
            }
            .sheet(item: $selectedProfile) { profile in
                ProfileDetailView(profile: profile)
            }
            .sheet(isPresented: $showingFormFill) {
                FormFillFlowView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("TrustNest Wheel")
                .font(.title2.weight(.semibold))
            Text("Select a member, then scan or fill a website form")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func activeProfileBanner(_ profile: Profile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active: \(profile.name)")
                    .font(.subheadline.weight(.semibold))
                Text(profile.relationshipType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { appState.clearActiveProfile() }
                .font(.caption)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
