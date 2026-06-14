import SwiftUI

struct TrustNestWheelView: View {
    let profiles: [Profile]
    let activeProfileId: String?
    let onProfileTap: (Profile) -> Void
    let onAddTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size * 0.34

            ZStack {
                wheelRing(center: center, diameter: size * 0.72)
                HouseCenterView().position(center)

                ForEach(Array(wheelItems.enumerated()), id: \.element.id) { index, item in
                    let angle = angleForIndex(index, total: wheelItems.count)
                    let position = CGPoint(
                        x: center.x + radius * cos(angle),
                        y: center.y + radius * sin(angle)
                    )

                    switch item {
                    case .profile(let profile):
                        MemberCircleView(
                            title: profile.name,
                            subtitle: profile.relationshipType.rawValue,
                            initials: profile.initials,
                            style: profile.individualId == activeProfileId ? .active : .member
                        ) {
                            onProfileTap(profile)
                        }
                        .position(position)

                    case .add:
                        MemberCircleView(
                            title: "ADD",
                            subtitle: "Member",
                            initials: "+",
                            style: .add,
                            action: onAddTap
                        )
                        .position(position)
                        .accessibilityIdentifier("addMemberCircle")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var wheelItems: [WheelItem] {
        profiles.map(WheelItem.profile) + [.add]
    }

    private func angleForIndex(_ index: Int, total: Int) -> CGFloat {
        let startAngle = -CGFloat.pi / 2
        let step = (2 * CGFloat.pi) / CGFloat(max(total, 1))
        return startAngle + step * CGFloat(index)
    }

    private func wheelRing(center: CGPoint, diameter: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.blue.opacity(0.25), lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .position(center)
    }
}

private enum WheelItem: Identifiable {
    case profile(Profile)
    case add

    var id: String {
        switch self {
        case .profile(let profile): return profile.individualId
        case .add: return "add"
        }
    }
}

struct HouseCenterView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.18, green: 0.42, blue: 0.74))
                .frame(width: 108, height: 108)
            VStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Nest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
