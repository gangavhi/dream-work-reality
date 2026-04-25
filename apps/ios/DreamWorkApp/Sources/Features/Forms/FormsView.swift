import SwiftUI

struct FormsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Demo forms") {
                    NavigationLink("School Intake") {
                        BlankSchoolRegistrationFormView()
                    }
                }
            }
            .navigationTitle("Forms")
            .navigationDestination(isPresented: $appState.showSchoolIntakeForm) {
                BlankSchoolRegistrationFormView()
            }
        }
    }
}
