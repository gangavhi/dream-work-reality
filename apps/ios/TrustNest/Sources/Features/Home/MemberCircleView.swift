import SwiftUI

struct MemberCircleView: View {
    enum Style {
        case member
        case active
        case add
    }

    let title: String
    let subtitle: String
    let initials: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 68, height: 68)
                        .overlay {
                            Circle().strokeBorder(borderColor, lineWidth: style == .add ? 2 : 1)
                        }

                    if style == .add {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(red: 0.18, green: 0.45, blue: 0.78))
                    } else {
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .member: return Color(red: 0.28, green: 0.58, blue: 0.88)
        case .active: return Color(red: 0.10, green: 0.45, blue: 0.30)
        case .add: return Color.white
        }
    }

    private var borderColor: Color {
        switch style {
        case .add: return Color(red: 0.35, green: 0.62, blue: 0.92)
        case .active: return .white.opacity(0.8)
        case .member: return .clear
        }
    }
}
