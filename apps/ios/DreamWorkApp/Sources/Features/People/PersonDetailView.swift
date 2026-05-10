import SwiftUI

struct PersonDetailView: View {
    let person: PersonRecord

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Entry ID") {
                    Text(person.id)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("personDetailEntryId")
                LabeledContent("Display name") {
                    Text(person.displayTitle)
                }
                .accessibilityIdentifier("personDetailDisplayName")
            }

            if !person.fields.isEmpty {
                Section("Fields") {
                    ForEach(Array(person.fields.enumerated()), id: \.offset) { _, field in
                        LabeledContent(field.key) {
                            Text(field.value)
                                .textSelection(.enabled)
                        }
                        .accessibilityIdentifier("personDetailField_\(field.key)")
                    }
                }
            }
        }
        .navigationTitle(person.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
