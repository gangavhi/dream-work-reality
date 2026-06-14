import SwiftUI
import WebKit

struct WebFormAssistView: View {
    let urlString: String
    let extractedFields: [FieldExtractionResult]
    let onFieldsDetected: ([WebFormField]) -> Void
    let onApplyValues: ([FieldExtractionResult]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var webViewStore = WebViewStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WebFormView(store: webViewStore, urlString: urlString)
            }
            .navigationTitle("Form Browser")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Detect Fields") {
                        webViewStore.detectFields { onFieldsDetected($0) }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Apply Auto-Fill") {
                        webViewStore.applyFields(extractedFields)
                    }
                    .disabled(extractedFields.isEmpty)
                }
            }
        }
    }
}

@MainActor
final class WebViewStore: ObservableObject {
    private weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func detectFields(completion: @escaping ([WebFormField]) -> Void) {
        guard let webView else { return }
        webView.evaluateJavaScript(WebFormScripts.detectFields) { result, _ in
            guard let raw = result as? [[String: String]] else {
                completion([])
                return
            }
            let fields = raw.enumerated().map { index, dict in
                WebFormField(
                    id: dict["id"] ?? "field-\(index)",
                    label: dict["label"] ?? dict["name"] ?? "Field \(index + 1)",
                    name: dict["name"] ?? "",
                    inputType: dict["type"] ?? "text"
                )
            }
            completion(fields)
        }
    }

    func applyFields(_ fields: [FieldExtractionResult]) {
        guard let webView else { return }
        for field in fields where !field.value.isEmpty {
            let script = WebFormScripts.setValue(
                fieldId: field.fieldId,
                name: field.fieldLabel,
                value: field.value
            )
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

struct WebFormView: UIViewRepresentable {
    let store: WebViewStore
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        store.attach(webView)
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

enum WebFormScripts {
    static let detectFields = """
    (function() {
      const fields = [];
      const elements = document.querySelectorAll('input, textarea, select');
      elements.forEach((el, index) => {
        if (el.type === 'hidden') return;
        const label = el.labels && el.labels[0] ? el.labels[0].innerText.trim() : '';
        fields.push({
          id: el.id || `field-${index}`,
          name: el.name || el.id || `field-${index}`,
          label: label || el.placeholder || el.name || `Field ${index + 1}`,
          type: el.type || el.tagName.toLowerCase()
        });
      });
      return fields;
    })();
    """

    static func setValue(fieldId: String, name: String, value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function() {
          let el = document.getElementById('\(fieldId)');
          if (!el) {
            el = document.querySelector(`[name="\(name)"]`);
          }
          if (!el) return false;
          el.value = '\(escaped)';
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        })();
        """
    }
}
