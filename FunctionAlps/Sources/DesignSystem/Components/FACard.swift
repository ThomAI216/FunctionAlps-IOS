import SwiftUI

/// Every card in the app is this surface, and this surface is always the see-through glass:
/// on iOS 26 it is Apple's clear Liquid Glass (the photo wall shows through, the pane refracts
/// what is behind it) with a white frost on top; before iOS 26 it is the web `GlassCard`
/// "seethrough" recipe (a white veil + shine bevel), never an opaque material. There is deliberately
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
    /// `true` for a small pane that sits INSIDE a glass card (the Apple Health tiles, chips over glass): a
    /// see-through veil with a hairline bevel and no shadow. Liquid Glass must not be nested — a second
    /// `glassEffect` inside a card renders as a milky slab, which is exactly what the owner saw (2026-09-14).
    var inset = false

    /// The wall behind the card decides how much frost it needs (see `frost(for:)`).
    @AppStorage(FAWalls.storageKey) private var wallKey: String = FAWalls.defaultKey

    init(cornerRadius: CGFloat, inset: Bool = false) {
        self.cornerRadius = cornerRadius
        self.inset = inset
    }

    /// White frost laid over the glass, under the card's content, so text on cards reads over the PHOTO
    /// walls. The owner's call (2026-09-30): 20 %, then 20 % more, then 20 % more again.
    static let frost = 0.60
    /// On the light gradient walls (Sage Fog, the default since 2026-11-06) 60 % frost turned every card into a
    /// flat white slab. Owner, 2026-11-10: "more glass effect, even with the new background, all the cards
    /// through all the app". The wall is already light, so text reads at far less frost; the rim light, the
    /// sheen and the shadow carry the glass.
    static let lightWallFrost = 0.34

    /// Frost for a wall: the photos keep the owner's 60 %, the light walls get the see-through glass.
    static func frost(for wall: Wall) -> Double {
        if case .photo = wall { return frost }
        return lightWallFrost
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let frost = Self.frost(for: FAWalls.resolved(wallKey))
        if inset {
            content
                .background(Color.white.opacity(0.12), in: shape)
                .overlay { Self.hairline(shape) }
        } else if #available(iOS 26.0, *) {
            content
                .background { Self.veil(shape, frost: frost) }
                .glassEffect(.clear, in: shape)
                .overlay { Self.rim(shape) }
                .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        } else {
            content
                .background { Self.veil(shape, frost: frost + 0.10) }
                .overlay { Self.rim(shape) }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        }
    }

    /// The frost, brighter at the top-left where the light falls, plus a soft sheen across the top third —
    /// what makes a pane read as glass instead of paper.
    private static func veil(_ shape: RoundedRectangle, frost: Double) -> some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Color.white.opacity(min(1, frost + 0.14)), Color.white.opacity(max(0, frost - 0.10))],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.32), location: 0), .init(color: Color.white.opacity(0), location: 0.38)],
                                      startPoint: .top, endPoint: .bottom))
        }
    }

    /// The edge: an almost invisible hairline (6 %, Thomas 2026-11-12: no white band or border around any card). The
    /// glass, the sheen and the shadow carry the surface; the edge only keeps its shape on light walls.
    private static func rim(_ shape: RoundedRectangle) -> some View {
        hairline(shape).allowsHitTesting(false)
    }

    private static func hairline(_ shape: RoundedRectangle) -> some View {
        shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
    }
}

extension View {
    /// The card glass behind a loose line that would otherwise sit straight on the photo wall — a back link,
    /// a section label, a text button, a hint. Same frost as the cards (owner, 2026-10-02: "otherwise we
    /// can't read"). For a block of content, use `FACard` instead.
    func faFrost(cornerRadius: CGFloat = 12, horizontal: CGFloat = 12, vertical: CGFloat = 6) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .modifier(FAGlassSurface(cornerRadius: cornerRadius))
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

/// The brand mark on its green tile, where the full logo image cannot load (the real logo lives in `FALogo`).
struct FABrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(FAColor.brand)
            FAMarkGlyph(color: .white, size: size * 0.62)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
