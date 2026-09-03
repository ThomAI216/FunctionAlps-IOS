import SwiftUI
import UIKit

// The web app's data-visual language: Apple-style rings with a hashed rest and a raised tube,
// hashed progress bars, the arrive-animation (every visual fills from zero on appear), and the
// pop-on used by the Home squares' choreography.

extension Color {
    /// Lighten (amt > 0, toward white) / darken (amt < 0, toward black) — `shade()` in ActivityRings.tsx.
    func shaded(_ amt: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        func mix(_ ch: CGFloat) -> CGFloat { amt >= 0 ? ch + (1 - ch) * amt : ch * (1 + amt) }
        return Color(red: Double(mix(r)), green: Double(mix(g)), blue: Double(mix(b)), opacity: Double(a))
    }
}

/// The web's `useMountFill`: 0 → 1 with a cubic ease-out over 2.4 s after a 100 ms settle.
struct MountFill: ViewModifier {
    @Binding var fill: Double
    var duration: Double = 2.4
    var delay: Double = 0.1

    func body(content: Content) -> some View {
        content.task {
            guard fill == 0 else { return }
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: duration)) { fill = 1 }
        }
    }
}

extension View {
    func mountFill(_ fill: Binding<Double>, duration: Double = 2.4, delay: Double = 0.1) -> some View {
        modifier(MountFill(fill: fill, duration: duration, delay: delay))
    }

    /// Hidden until `on`, then a small rise-and-settle spring (`Pop.tsx`).
    func popIn(_ on: Bool) -> some View {
        self
            .opacity(on ? 1 : 0)
            .scaleEffect(on ? 1 : 0.85)
            .offset(y: on ? 0 : 6)
            .animation(.spring(response: 0.38, dampingFraction: 0.58), value: on)
            .allowsHitTesting(false)
    }
}

/// Diagonal hatch tile (`repeating-linear-gradient(135deg …)`) for rings and bars.
enum HatchTile {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    static func image(color: Color, cell: CGFloat = 5, lineWidth: CGFloat = 1.4, opacity: Double = 0.5) -> UIImage {
        let key = "\(color.description)-\(cell)-\(lineWidth)-\(opacity)"
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: cell, height: cell), format: format).image { ctx in
            let c = ctx.cgContext
            c.setStrokeColor(UIColor(color).withAlphaComponent(opacity).cgColor)
            c.setLineWidth(lineWidth)
            c.move(to: CGPoint(x: 0, y: cell)); c.addLine(to: CGPoint(x: cell, y: 0))
            c.move(to: CGPoint(x: -cell, y: cell)); c.addLine(to: CGPoint(x: cell, y: -cell))
            c.move(to: CGPoint(x: 0, y: 2 * cell)); c.addLine(to: CGPoint(x: 2 * cell, y: 0))
            c.strokePath()
        }
        cache[key] = image
        return image
    }
}

/// One Apple-style ring: hashed rest in the ring's own colour, a raised (top-lit → shaded) arc
/// with an inner specular highlight, filling from zero on appear.
struct ActivityRing<Center: View>: View {
    let pct: Double
    var color: Color = Color(hex: 0x8FBF97)
    var size: CGFloat = 104
    var strokeWidth: CGFloat = 13
    var hashedTrack = true
    var raised = true
    var trackColor: Color = Color(red: 120 / 255, green: 150 / 255, blue: 130 / 255, opacity: 0.32)
    @ViewBuilder var center: Center
    @State private var fill: Double = 0

    var body: some View {
        let p = max(0, min(1, pct)) * fill
        let r = size / 2 - strokeWidth / 2
        let hr = r - strokeWidth * 0.26
        ZStack {
            Circle()
                .strokeBorder(hashedTrack ? AnyShapeStyle(ImagePaint(image: Image(uiImage: HatchTile.image(color: color)))) : AnyShapeStyle(trackColor), lineWidth: strokeWidth)
                .frame(width: size, height: size)
            if hashedTrack {
                Circle().strokeBorder(trackColor.opacity(0.35), lineWidth: strokeWidth).frame(width: size, height: size)
            }
            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    raised ? AnyShapeStyle(LinearGradient(colors: [color.shaded(0.42), color, color.shaded(-0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(color),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: r * 2, height: r * 2)
                .rotationEffect(.degrees(-90))
            if raised, p > 0, hr > 0 {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(color.shaded(0.6), style: StrokeStyle(lineWidth: strokeWidth * 0.32, lineCap: .round))
                    .frame(width: hr * 2, height: hr * 2)
                    .rotationEffect(.degrees(-90))
                    .opacity(0.55)
            }
            center
        }
        .frame(width: size, height: size)
        .mountFill($fill)
    }
}

/// A hashed progress bar: hatch rest, tube-shaded fill with a crisp rim at the tip, top sheen.
struct HashedBar: View {
    let color: Color
    let pct: Double
    var height: CGFloat = 7
    var raised = false
    @State private var fill: Double = 0

    var body: some View {
        let p = max(0, min(1, pct)) * fill
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.1))
                Capsule().fill(ImagePaint(image: Image(uiImage: HatchTile.image(color: color, cell: 6, lineWidth: 1.5, opacity: 0.4))))
                ZStack(alignment: .trailing) {
                    Capsule().fill(LinearGradient(colors: [color.shaded(-0.32), color, color.shaded(0.48)], startPoint: .leading, endPoint: .trailing))
                    if p > 0.02, p < 0.992 {
                        Rectangle().fill(Color.white.opacity(0.78)).frame(width: 1.75).padding(.vertical, 0.75)
                    }
                }
                .frame(width: max(0, geo.size.width * CGFloat(p)))
                .clipShape(Capsule())
                Capsule().fill(Color.white.opacity(raised ? 0.42 : 0.32)).frame(height: 1.5).frame(maxHeight: .infinity, alignment: .top).padding(.horizontal, height / 2)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .mountFill($fill)
    }
}

/// A calm "this arrives later" screen on the wall, for the tabs whose engine is still server-side work.
struct ComingSoonView: View {
    let title: String
    let message: String
    var systemImage = "sparkles"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.lg) {
                Text(title)
                    .font(FATypography.largeTitle)
                    .foregroundStyle(FAColor.ink)
                    .padding(.top, 38)
                FACard {
                    HStack(spacing: FASpacing.md) {
                        ZStack {
                            Circle().fill(FAColor.accent.opacity(0.14))
                            Image(systemName: systemImage).foregroundStyle(FAColor.accent)
                        }
                        .frame(width: 40, height: 40)
                        Text(message)
                            .font(FATypography.callout)
                            .foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}
