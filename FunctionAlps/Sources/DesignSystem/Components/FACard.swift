import SwiftUI

/// The web app's `GlassCard` (liquid, light treatment) in native materials: blurred backdrop,
/// white 50 % tint, radius 25, a glossy shine bevel (bright top-left → faint bottom-right) and a
/// soft drop shadow. Every card in the app is this surface.
struct FACard<Content: View>: View {
    var padded = true
    /// `.clear` = fully see-through (the web's "seethrough" recipe); `.regular` = the light liquid glass.
    var glass: GlassKind = .regular
    @ViewBuilder let content: Content

    enum GlassKind { case regular, clear }

    var body: some View {
        content
            .padding(padded ? 18 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(kind: glass, cornerRadius: FACornerRadius.glass))
    }
}

/// The glass itself. On iOS 26 this is Apple's Liquid Glass (real refraction of the wall behind);
/// earlier systems get the web recipe (white tint + shine bevel) with no opaque material.
struct FAGlassSurface: ViewModifier {
    let kind: FACard<EmptyView>.GlassKind
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(kind == .clear ? .clear : .regular.tint(Color.white.opacity(0.22)), in: shape)
                .shadow(color: .black.opacity(kind == .clear ? 0.10 : 0.16), radius: 14, y: 8)
        } else {
            content
                .background(Color.white.opacity(kind == .clear ? 0.20 : 0.42), in: shape)
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
