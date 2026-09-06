import SwiftUI

/// The colours the slosh shader ramps through: deep → mid → base → light → highlight.
struct SloshPalette: Sendable, Equatable {
    let c1: Color, c2: Color, c3: Color, c4: Color, c5: Color

    /// The owner's Metal Forge blues, the dark end lifted (2026-09-06: "the far side was too dark").
    static let metalForge = SloshPalette(c1: Color(hex: 0x0B2266), c2: Color(hex: 0x10318F), c3: Color(hex: 0x0F3DB2), c4: Color(hex: 0x4794FF), c5: Color(hex: 0xC7E6FF))

    /// A bar's own colour as a five-stop ramp — the macro / marker bars keep their locked hues.
    static func derived(from color: Color) -> SloshPalette {
        SloshPalette(c1: color.shaded(-0.48), c2: color.shaded(-0.26), c3: color.shaded(-0.08), c4: color.shaded(0.22), c5: color.shaded(0.78))
    }
}

/// The animated "slosh" progress fill (Metal shader `slosh`), sized by its parent. The empty part is
/// transparent so whatever sits behind (the hashed track) shows through. Reduced Motion freezes the wave.
struct SloshFill: View {
    /// 0…1, already eased by the caller (the bars mount from zero with `mountFill`).
    let progress: Double
    var palette: SloshPalette = .metalForge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
            let p = Float(max(0, min(1, progress)))
            let pal = palette
            Rectangle()
                .fill(Color.white)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.slosh(
                        .float2(proxy.size), .float(t), .float(p),
                        .color(pal.c1), .color(pal.c2), .color(pal.c3), .color(pal.c4), .color(pal.c5)
                    ))
                }
        }
        .accessibilityHidden(true)
    }
}

/// The ring version (Metal shader `sloshRing`): the same effect around a circle, the fill starting at the
/// top and running clockwise, `thickness` points wide. Sized by its parent (a square).
struct SloshRingFill: View {
    let progress: Double
    let thickness: CGFloat
    var palette: SloshPalette = .metalForge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
            let p = Float(max(0, min(1, progress)))
            let w = Float(thickness)
            let pal = palette
            Rectangle()
                .fill(Color.white)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.sloshRing(
                        .float2(proxy.size), .float(t), .float(p), .float(w),
                        .color(pal.c1), .color(pal.c2), .color(pal.c3), .color(pal.c4), .color(pal.c5)
                    ))
                }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Slosh bar") {
    VStack(spacing: 18) {
        ForEach([0.73, 0.4, 1.0], id: \.self) { v in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                SloshFill(progress: v)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        HashedBar(color: FAColor.protein, pct: 0.62, height: 14)
        HashedBar(color: FAColor.fat, pct: 0.35, height: 12)
        HStack(spacing: 24) {
            ActivityRing(pct: 0.73) { Text("73").font(FATypography.display(28)).foregroundStyle(FAColor.ink) }
            ActivityRing(pct: 0.4, color: FAColor.protein, size: 78, strokeWidth: 10) { EmptyView() }
        }
    }
    .padding(24)
    .background(Color(hex: 0x10131B))
}
