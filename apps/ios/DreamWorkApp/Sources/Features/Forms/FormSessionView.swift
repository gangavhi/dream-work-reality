import SwiftUI
import UIKit

struct FormSessionView: View {
    @EnvironmentObject private var appState: AppState

    let template: FormTemplate

    @State private var selectedPersonID: String = ""
    @State private var copiedFieldKey: String?
    @State private var bannerMessage: String?

    var body: some View {
        List {
            Section {
                Text(template.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Form subject") {
                if appState.people.isEmpty {
                    Text("Add a person under the People tab to autofill from their profile.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Profile", selection: $selectedPersonID) {
                        ForEach(appState.people) { person in
                            Text(person.displayTitle).tag(person.id)
                        }
                    }
                }
            }

            Section("Checklist — tap Copy, then paste in the other app") {
                ForEach(template.fields) { requirement in
                    checklistRow(requirement)
                }
            }

            if !appState.people.isEmpty {
                Section {
                    Button("Copy all filled values") {
                        copyAllFilled()
                    }
                }
            }
        }
        .appListChrome()
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedPersonID.isEmpty {
                selectedPersonID = appState.people.first?.id ?? ""
            }
            appState.refreshPeopleList()
        }
        .overlay(alignment: .bottom) {
            if let bannerMessage {
                Text(bannerMessage)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bannerMessage)
    }

    @ViewBuilder
    private func checklistRow(_ requirement: FormFieldRequirement) -> some View {
        let value = currentPerson?.value(for: requirement.profileKey) ?? ""
        let isMissing = value.isEmpty

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(requirement.label)
                    .fieldLabelStyle()
                Spacer()
                if isMissing {
                    Text("Missing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if copiedFieldKey == requirement.profileKey {
                    Text("Copied")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if let hint = requirement.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isMissing {
                Text("Add this in People → Edit profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(value)
                    .fieldValueStyle(prominent: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyValue(value, fieldKey: requirement.profileKey, label: requirement.label)
                } label: {
                    Label("Copy to clipboard", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentPerson: PersonRecord? {
        appState.people.first { $0.id == selectedPersonID }
    }

    private func copyValue(_ value: String, fieldKey: String, label: String) {
        UIPasteboard.general.string = value
        copiedFieldKey = fieldKey
        showBanner("Copied \(label)")
    }

    private func copyAllFilled() {
        guard let person = currentPerson else { return }
        let lines = template.fields.compactMap { req -> String? in
            let value = person.value(for: req.profileKey)
            guard !value.isEmpty else { return nil }
            return "\(req.label): \(value)"
        }
        guard !lines.isEmpty else {
            showBanner("No filled fields for this template")
            return
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        showBanner("Copied \(lines.count) field(s)")
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }
}
