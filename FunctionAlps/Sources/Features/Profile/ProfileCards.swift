import SwiftUI

// The Profile tab's shared pieces, one-to-one with the Expo `(tabs)/profile.tsx` and its subpages:
// section labels, the round-icon row card, the back link, the opaque reading surface, and the
// closed markdown subset the legal documents use. Light palette only (the wall is light).

enum ProfilePalette {
    static let hairline = Color(hex: 0x1A1A16, opacity: 0.08)
    static let muted = FAColor.stone
    static let surface = Color.white.opacity(0.7)
    static let surfaceSoft = Color.white.opacity(0.45)
    static let accentSoft = Color(hex: 0x4A8A5C, opacity: 0.14)
    /// `t.gold` retired in-app → the working forest accent.
    static let gold = FAColor.forestSoft
    static let red = Color(hex: 0xC0453A)
    /// `opaqueSurface('dots')`: the warm reading surface + its border.
    static let readingBg = FAColor.warm
    static let readingBorder = Color(hex: 0x1A1A16, opacity: 0.10)
}

/// `SectionLabel`: uppercase 11 bold, tracking 1.4, muted; an optional forest action on the right.
struct ProfileSectionLabel: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(FATypography.sans(11, .bold, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(ProfilePalette.muted)
            Spacer()
            if let action {
                Button { onAction?() } label: {
                    Text(action)
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption2))
                        .foregroundStyle(ProfilePalette.gold)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 11)
    }
}

/// The settings-style section label (10.5, no action, padded 2).
struct SettingsSectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(FATypography.sans(10.5, .bold, relativeTo: .caption2))
            .tracking(1.4)
            .foregroundStyle(ProfilePalette.muted)
            .padding(.horizontal, 2)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A glass card with a 42 pt round icon, a title, a sub-line and the chevron (baseline / feedback / learn).
struct ProfileIconRowCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tintHex: UInt32 = 0x4A8A5C
    var borderHex: UInt32? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FACard {
                HStack(spacing: 13) {
                    ZStack {
                        Circle().fill(Color(hex: tintHex, opacity: 0.16))
                        Circle().strokeBorder(Color(hex: tintHex, opacity: 0.45), lineWidth: 1)
                        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: tintHex))
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(subtitle).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.gold)
                }
            }
            .overlay {
                if let borderHex {
                    RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                        .strokeBorder(Color(hex: borderHex, opacity: 0.45), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// `‹ Title` — the subpages' back link (bold 13, paddingVertical 12). Pops the stack.
struct BackLink: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Text("‹ " + title)
                .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                .foregroundStyle(FAColor.ink)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
    }
}

/// The centred-title header with a chevron back (Settings, Messages, My Care Plan).
struct CenteredHeader: View {
    let title: String
    var hairline = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).foregroundStyle(FAColor.ink)
                    .frame(width: 36, height: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
            Text(title).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink).frame(maxWidth: .infinity)
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if hairline { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
    }
}

/// `opaqueSurface`: paragraphs sit on a flat warm surface, never on glass (body copy over the wall is hard to read).
struct ReadingSurface<Content: View>: View {
    var padded = true
    var borderHex: UInt32? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padded ? 18 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProfilePalette.readingBg, in: RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                    .strokeBorder(borderHex.map { Color(hex: $0, opacity: 0.45) } ?? ProfilePalette.readingBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

/// A plain surface card (`t.surface`, radius 16, padding 14) — the privacy/help/data screens' rows.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 14
    var radius: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Settings / privacy row: square icon tile, label (+ sub), chevron.
struct SettingsRow: View {
    let symbol: String
    let label: String
    var sub: String? = nil
    var tintHex: UInt32 = 0x4A8A5C
    var destructive = false
    var first = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(destructive ? ProfilePalette.red.opacity(0.15) : Color(hex: tintHex, opacity: 0.15))
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(destructive ? ProfilePalette.red : Color(hex: tintHex))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(destructive ? ProfilePalette.red : FAColor.ink)
                    if let sub {
                        Text(sub).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(destructive ? ProfilePalette.red.opacity(0.5) : ProfilePalette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
    }
}

/// The closed markdown subset the legal documents use (`## h2`, `### h3`, `- bullet`, paragraphs).
struct LegalMarkdownView: View {
    let markdown: String
    var hideTitle = false

    var body: some View {
        let blocks = LegalMarkdown.parse(markdown)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .h2(let text):
                    if !hideTitle {
                        Text(text).font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.ink).padding(.bottom, 10)
                    }
                case .h3(let text):
                    Text(text).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).padding(.top, 14).padding(.bottom, 6)
                case .paragraph(let text):
                    Text(text).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5).padding(.bottom, 8)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                                Text(item).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// The forest pill button (radius 200, paddingVertical 15, charcoal bold 15).
struct ForestPillButton: View {
    let title: String
    var enabled = true
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(FAColor.charcoal) }
                Text(title).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.charcoal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(FAColor.forestSoft, in: Capsule())
            .opacity(enabled && !busy ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}
