import SwiftUI

/// App-wide visual language: readable type, clear hierarchy, generous tap targets.
enum AppTheme {
    static let accent = Color.accentColor
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let minTapHeight: CGFloat = 52

    static func cardBackground(in scheme: ColorScheme) -> Color {
        Color(.secondarySystemGroupedBackground)
    }
}

extension Text {
    func appHelperText() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func appSectionTitle() -> some View {
        font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

extension View {
    func appListChrome() -> some View {
        listStyle(.insetGrouped)
    }

    func appScreenBackground() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

/// Large tappable row for primary flows (scan, upload, navigation).
struct AppActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = AppTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.cardPadding)
            .frame(minHeight: AppTheme.minTapHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Compact step indicator for onboarding-style guidance.
struct AppStepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Soft pill for roles, tags, and status chips.
struct AppTag: View {
    let text: String
    var color: Color = AppTheme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}
