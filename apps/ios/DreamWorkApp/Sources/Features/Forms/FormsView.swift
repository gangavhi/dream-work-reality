import SwiftUI

struct FormsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a form type, pick a template, then copy profile fields into Safari or any other app. Your data never leaves this device.")
                        .appHelperText()
                }

                Section {
                    ForEach(FormCategory.allCases) { category in
                        NavigationLink {
                            FormCategoryDetailView(category: category)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: category.iconName)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.rawValue)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(category.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } header: {
                    Text("Categories")
                }
            }
            .appListChrome()
            .navigationTitle("Forms")
        }
    }
}
