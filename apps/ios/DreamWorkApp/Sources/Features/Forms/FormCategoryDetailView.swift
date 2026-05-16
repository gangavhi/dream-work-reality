import SwiftUI

struct FormCategoryDetailView: View {
    let category: FormCategory

    var body: some View {
        List {
            Section {
                Label(category.subtitle, systemImage: category.iconName)
                    .foregroundStyle(.secondary)
            }

            Section("Templates") {
                let templates = FormTemplateLibrary.templates(in: category)
                if templates.isEmpty {
                    Text("Templates for this category are coming soon.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(templates) { template in
                        NavigationLink {
                            FormSessionView(template: template)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                Text(template.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(category.rawValue)
    }
}
