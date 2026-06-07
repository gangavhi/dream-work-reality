import SwiftUI

struct MustHaveDocumentsChecklist: View {
    let person: PersonRecord

    private var stashedTypes: Set<String> {
        SubmissionDocumentStore.shared.stashedDocumentTypes(personId: person.id)
    }

    var body: some View {
        Section {
            ForEach(MustHaveDocumentCategory.allCases) { category in
                HStack {
                    Image(systemName: category.isComplete(person: person, stashedTypes: stashedTypes) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(category.isComplete(person: person, stashedTypes: stashedTypes) ? .green : .secondary)
                    Text(category.rawValue)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Must-have documents")
        } footer: {
            Text("All data stays on this device. Scanned files are encrypted locally — nothing is sent to remote AI.")
                .font(.caption)
        }
    }
}
