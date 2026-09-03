import SwiftUI

/// Every card in the app is this surface, and this surface is always the see-through glass:
/// on iOS 26 it is Apple's clear Liquid Glass (the Sage wall and its dots show through, the
/// pane refracts what is behind it); before iOS 26 it is the web `GlassCard` "seethrough"
/// recipe (a faint white veil + shine bevel), never an opaque material. There is deliberately
/// no opaque or tinted variant — the owner's rule (2026-09-03) is that all cards on every screen,
/// including future ones, and the floating tab bar use exactly this glass.
struct FACard<Content: View>: View {
    var padded = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padded ? 18 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
    }
}

/// The glass itself — the one recipe shared by cards and the tab bar. Use this modifier (or
/// `FACard`) for any new surface; never `.ultraThinMaterial`, `.regularMaterial` or a solid fill.
struct FAGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: shape)
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
        } else {
            content
                .background(Color.white.opacity(0.20), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.72), Color.white.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5
                    )
                }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        }
    }
}

struct FASection<Content: View>: View {
    let title: String
    var kicker: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.sm) {
            if let kicker {
                Text(kicker.uppercased())
                    .font(FATypography.label)
                    .foregroundStyle(FAColor.brand)
                    .tracking(0.8)
            }
            Text(title)
                .font(FATypography.title)
                .foregroundStyle(FAColor.ink)
            content
        }
    }
}

struct FAMetricCard: View {
    let label: String
    let value: String
    var caption: String? = nil

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.xs) {
                Text(label).font(FATypography.label).foregroundStyle(FAColor.inkSecondary)
                Text(value).font(FATypography.metric).foregroundStyle(FAColor.ink)
                if let caption {
                    Text(caption).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FAListRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: FASpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(FAColor.brand)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FATypography.body).foregroundStyle(FAColor.ink)
                if let subtitle {
                    Text(subtitle).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, FASpacing.xs)
        .contentShape(Rectangle())
    }
}

/// Placeholder brand mark (the real logo lives in `FALogo`).
struct FABrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(FAColor.brand)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
