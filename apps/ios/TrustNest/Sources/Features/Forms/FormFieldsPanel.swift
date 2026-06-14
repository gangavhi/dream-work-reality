import SwiftUI
import QuickLook

struct FormFieldsPanel: View {
    let fields: [FieldExtractionResult]
    let onManualOverride: (String, String) -> Void

    @State private var previewURL: URL?
    @State private var editingFieldId: String?
    @State private var draftValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-Filled Fields")
                .font(.headline)

            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 8) {
                    Text(field.fieldLabel)
                        .font(.subheadline.weight(.semibold))

                    if field.candidates.count > 1 && field.value.isEmpty {
                        Text("Conflicting evidence found. Choose a source or enter a value manually.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        ForEach(field.candidates) { candidate in
                            Button(candidate.documentType ?? URL(fileURLWithPath: candidate.filePath).lastPathComponent) {
                                onManualOverride(field.id, candidate.excerpt)
                            }
                            .font(.caption)
                        }
                    } else {
                        TextField("Value", text: binding(for: field))
                            .textFieldStyle(.roundedBorder)
                    }

                    EvidenceBadge(
                        sourceName: field.sourceDocumentName,
                        isManualOverride: field.isManualOverride
                    ) {
                        let url = URL(string: field.sourceFilePath) ?? URL(fileURLWithPath: field.sourceFilePath)
                        previewURL = url
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .sheet(item: $previewURL) { url in
            DocumentPreviewView(url: url)
        }
    }

    private func binding(for field: FieldExtractionResult) -> Binding<String> {
        Binding(
            get: { field.value },
            set: { onManualOverride(field.id, $0) }
        )
    }
}

struct EvidenceBadge: View {
    let sourceName: String
    let isManualOverride: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isManualOverride ? "pencil.circle.fill" : "doc.text.magnifyingglass")
                Text(isManualOverride ? "Manual override" : "[Source: \(sourceName)]")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("evidenceBadge")
    }
}

struct DocumentPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .navigationTitle("Source Document")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        context.coordinator.url = url
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL?

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { url == nil ? 0 : 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url! as NSURL
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
