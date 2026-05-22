import SwiftUI

/// Shared typography for extracted profile field values (readable, high-contrast).
enum FieldDisplayStyle {
    static let valueFont: Font = .body.weight(.semibold)
    static let prominentValueFont: Font = .title3.weight(.semibold)
    static let labelFont: Font = .subheadline.weight(.medium)
    static let metaFont: Font = .caption

    static let valueColor: Color = .primary
    static let labelColor: Color = .secondary
    static let metaColor: Color = .secondary
}

extension Text {
    func fieldValueStyle(prominent: Bool = false) -> some View {
        font(prominent ? FieldDisplayStyle.prominentValueFont : FieldDisplayStyle.valueFont)
            .foregroundStyle(FieldDisplayStyle.valueColor)
    }

    func fieldLabelStyle() -> some View {
        font(FieldDisplayStyle.labelFont)
            .foregroundStyle(FieldDisplayStyle.labelColor)
    }

    func fieldMetaStyle() -> some View {
        font(FieldDisplayStyle.metaFont)
            .foregroundStyle(FieldDisplayStyle.metaColor)
    }
}

extension View {
    /// Applies readable body text styling to form inputs showing profile data.
    func fieldInputStyle() -> some View {
        font(FieldDisplayStyle.valueFont)
            .foregroundStyle(FieldDisplayStyle.valueColor)
    }
}

/// Label + value row with emphasized, easy-to-read data.
struct FieldValueRow: View {
    let label: String
    let value: String
    var prominent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .fieldLabelStyle()
            Text(value)
                .fieldValueStyle(prominent: prominent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `LabeledContent` with a darker, larger value on the trailing side.
struct FieldLabeledContent: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .fieldValueStyle()
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
                .fieldLabelStyle()
        }
    }
}

/// Read-only field row with a per-field edit control; expands to a text field while editing.
struct EditableFieldRow: View {
    let label: String
    let profileKey: String
    @Binding var text: String
    @Binding var isEditing: Bool
    var originalValue: String = ""
    var onCommit: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isModified: Bool {
        trimmedText != originalValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .fieldLabelStyle()
                if isModified, !isEditing {
                    Text("Edited")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 8)
                editControls
            }

            if isEditing {
                TextField(label, text: $text, axis: .vertical)
                    .fieldInputStyle()
                    .textContentType(ProfileFieldInputTraits.textContentType(for: profileKey))
                    .keyboardType(ProfileFieldInputTraits.keyboardType(for: profileKey))
                    .textInputAutocapitalization(ProfileFieldInputTraits.textInputAutocapitalization(for: profileKey))
                    .autocorrectionDisabled(ProfileFieldInputTraits.autocorrectionDisabled(for: profileKey))
                    .lineLimit(1 ... 4)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(commitEdit)
            } else {
                Button {
                    beginEdit()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(trimmedText.isEmpty ? "Tap to add" : trimmedText)
                            .fieldValueStyle()
                            .foregroundStyle(trimmedText.isEmpty ? FieldDisplayStyle.labelColor : FieldDisplayStyle.valueColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(label)")
                .accessibilityHint(trimmedText.isEmpty ? "Add a value for this field" : "Change \(label)")
            }
        }
        .padding(.vertical, 4)
        .onChange(of: isEditing) { _, editing in
            if editing {
                DispatchQueue.main.async {
                    isFocused = true
                }
            } else {
                isFocused = false
            }
        }
    }

    @ViewBuilder
    private var editControls: some View {
        if isEditing {
            Button("Done", action: commitEdit)
                .font(.subheadline.weight(.semibold))
        } else {
            Button {
                beginEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(label)")
        }
    }

    private func beginEdit() {
        isEditing = true
    }

    private func commitEdit() {
        text = trimmedText
        isEditing = false
        isFocused = false
        onCommit?()
    }
}
