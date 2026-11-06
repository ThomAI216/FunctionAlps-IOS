import SwiftUI

/// A team member's round photo, with the initials on the forest disc while it loads and when it fails (or when there is
/// no photo, as in the showcase). The accessibility label is the name.
struct CareAvatar: View {
    let member: CareMember?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            initialsDisc
            if let url = CareTeamLogic.photoURL(member?.photoPath) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(FAColor.forestSoft.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member?.name ?? String(localized: "careTeam.avatar.generic", defaultValue: "Your team"))
    }

    private var initialsDisc: some View {
        ZStack {
            Circle().fill(FAColor.forestGlow)
            if let member, !CareTeamLogic.initials(member.name).isEmpty {
                Text(CareTeamLogic.initials(member.name))
                    .font(FATypography.display(size * 0.4, relativeTo: .title3)).foregroundStyle(FAColor.forest)
            } else {
                Image(systemName: "bubble.left").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
            }
        }
    }
}

/// Profile's "Your care team": each member (photo, name, title), then the primary pill into Messages.
struct CareTeamCard: View {
    let team: CareTeam
    let onMessage: () -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(team.members) { member in
                    HStack(spacing: 12) {
                        CareAvatar(member: member, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(FATypography.display(17, relativeTo: .headline)).foregroundStyle(FAColor.ink).lineLimit(1)
                            if let title = CareTeamLogic.title(member, french: CareTeamLogic.appIsFrench) {
                                Text(title).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                CarePill(title: String(localized: "profile.team.message", defaultValue: "Message your team"), action: onMessage)
            }
        }
    }
}

/// The primary pill used by the care-team cards (forest fill, white label).
struct CarePill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(FAColor.brand, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
