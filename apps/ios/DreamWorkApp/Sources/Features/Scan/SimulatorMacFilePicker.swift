import SwiftUI
import UniformTypeIdentifiers
import UIKit

#if targetEnvironment(simulator)
/// Presents the system document picker as sheet content (works in Simulator).
struct SimulatorMacFilePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: DocumentImportHelper.allowedContentTypes)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SimulatorMacFilePicker

        init(parent: SimulatorMacFilePicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
#endif
