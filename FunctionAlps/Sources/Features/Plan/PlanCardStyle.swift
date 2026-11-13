import SwiftUI

/// A plan card: the app's glass card (`FACard`, which is `FAGlassSurface`, the design-system Liquid Glass) with a soft,
/// translucent colour wash laid on top. The wash is an overlay at low opacity, fading from the top-left to clear, so the
/// glass material and whatever is behind it still show through. Nothing here is an opaque fill.
struct TintedFACard<Content: View>: View {
    let tint: UInt32
    @ViewBuilder let content: Content

    var body: some View {
        FACard { content }
            .overlay {
                RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                    .fill(PlanWash.gradient(tint, strong: false))
                    .allowsHitTesting(false)
            }
    }
}

/// A line inside a plan card (a hypothesis, a complaint, a win) with its own colour wash: a small inset pane of the
/// same glass as the card, with the tint on top, so it reads as part of the same surface.
struct TintedInsetRow<Content: View>: View {
    let tint: UInt32
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(cornerRadius: FACornerRadius.sm, inset: true))
            .overlay {
                RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous)
                    .fill(PlanWash.gradient(tint, strong: true))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }
}

enum PlanWash {
    /// Diagonal: the tint at its strongest in the top-left corner, fading to clear bottom-right. Opacities are kept low
    /// so text stays readable on the glass.
    static func gradient(_ hex: UInt32, strong: Bool) -> LinearGradient {
        let top = strong ? 0.22 : 0.12
        let mid = strong ? 0.08 : 0.04
        return LinearGradient(
            stops: [
                .init(color: Color(hex: hex, opacity: top), location: 0),
                .init(color: Color(hex: hex, opacity: mid), location: 0.55),
                .init(color: Color(hex: hex, opacity: 0), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
