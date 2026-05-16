import SwiftUI

struct FormsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a form category, choose a template, then copy profile fields into Safari or any other app. Data stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Categories") {
                    ForEach(FormCategory.allCases) { category in
                        NavigationLink {
                            FormCategoryDetailView(category: category)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                        .font(.headline)
                                    Text(category.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: category.iconName)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Forms")
        }
    }
}
