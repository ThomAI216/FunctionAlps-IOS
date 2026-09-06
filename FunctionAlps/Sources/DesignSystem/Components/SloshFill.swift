import SwiftUI

/// The colours the slosh shader ramps through: deep → mid → base → light → highlight.
struct SloshPalette: Sendable, Equatable {
    let c1: Color, c2: Color, c3: Color, c4: Color, c5: Color

    /// The owner's Metal Forge blues (`#040819 · #061645 · #0F3DB2 · #4794FF · #C7E6FF`).
    static let metalForge = SloshPalette(c1: Color(hex: 0x040819), c2: Color(hex: 0x061645), c3: Color(hex: 0x0F3DB2), c4: Color(hex: 0x4794FF), c5: Color(hex: 0xC7E6FF))

    /// A bar's own colour as a five-stop ramp — the macro / marker bars keep their locked hues.
    static func derived(from color: Color) -> SloshPalette {
        SloshPalette(c1: color.shaded(-0.82), c2: color.shaded(-0.55), c3: color.shaded(-0.12), c4: color.shaded(0.22), c5: color.shaded(0.78))
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
        HashedBar(color: FAColor.protein, pct: 0.62, height: 10)
        HashedBar(color: FAColor.fat, pct: 0.35, height: 7)
    }
    .padding(24)
    .background(Color(hex: 0x10131B))
}
