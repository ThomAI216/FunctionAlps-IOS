import SwiftUI

// The Expo app's meal visuals, native: the score wheel, the shimmer, the colour-cycling FA mark,
// the plate scan canvas with its reticle, the "reading your words" canvas, and the placeholder bank.

/// The brand `ScoreRing` (viewBox 36, r 15.9, stroke 3.4, the number inside in the stroke colour).
struct ScoreWheel: View {
    let value: Int
    let color: Color
    var size: CGFloat = 54
    var track: Color = Color.black.opacity(0.08)

    var body: some View {
        let dash = CGFloat(max(0, min(100, value))) / 100
        ZStack {
            Circle().stroke(track, lineWidth: size * 3.4 / 36)
            Circle()
                .trim(from: 0, to: dash)
                .stroke(color, style: StrokeStyle(lineWidth: size * 3.4 / 36, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(FATypography.sans(size * 11 / 36, .bold, relativeTo: .caption))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(value) out of 100")
    }
}

/// A soft moving highlight where a number will be — read as a wait, never as a zero.
struct ShimmerBar: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil
    var radius: CGFloat = 6

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.07))
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: -geo.size.width * 0.5 + geo.size.width * 1.5 * t)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// The FA mark "polishing" loader: grows to its biggest and the colour crossfades to the next one
/// right at that peak, then shrinks and grows back before changing again. One clock drives both.
struct ColorCycleMark: View {
    var size: CGFloat = 44
    var interval: Double = 1.7
    private static let logos = ["fa-blue", "fa-orange", "fa-green", "fa-red", "fa-purple", "fa-yellow"]
    private static let xfade = 0.3

    var body: some View {
        TimelineView(.animation) { context in
            let beat = context.date.timeIntervalSinceReferenceDate / interval
            let phase = beat.truncatingRemainder(dividingBy: 1)
            let n = Int(beat) % Self.logos.count
            let nx = (n + 1) % Self.logos.count
            let raw = phase > 1 - Self.xfade ? (phase - (1 - Self.xfade)) / Self.xfade : 0
            let t = 0.5 - 0.5 * cos(raw * .pi)
            ZStack {
                FABundledImage(name: Self.logos[n]).opacity(1 - t)
                FABundledImage(name: Self.logos[nx]).opacity(t)
            }
            .frame(width: size, height: size)
            .scaleEffect(1.0 + 0.1 * cos(phase * 2 * .pi))
        }
        .accessibilityHidden(true)
    }
}

/// Four corner brackets framing the plate (green when done).
struct Reticle: View {
    let done: Bool

    var body: some View {
        let c: Color = done ? FAColor.forestSoft : Color(hex: 0x1A1A16, opacity: 0.45)
        ZStack {
            corner(c).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            corner(c).rotationEffect(.degrees(90)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            corner(c).rotationEffect(.degrees(-90)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            corner(c).rotationEffect(.degrees(180)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.4), value: done)
        .accessibilityHidden(true)
    }

    private func corner(_ color: Color) -> some View {
        let s: CGFloat = 26
        return Path { p in
            p.move(to: CGPoint(x: 0, y: s))
            p.addLine(to: CGPoint(x: 0, y: 8))
            p.addQuadCurve(to: CGPoint(x: 8, y: 0), control: .zero)
            p.addLine(to: CGPoint(x: s, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: s, height: s)
    }
}

/// Photo path: the plate with one clean scanning sweep — identical for every meal.
struct PhotoScanCanvas: View {
    let image: UIImage
    let size: CGFloat
    let done: Bool

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped()
            if !done {
                TimelineView(.animation) { context in
                    let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 1.7
                    let p = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2 // ease in-out quad
                    let opacity = raw < 0.08 ? raw / 0.08 : raw > 0.92 ? (1 - raw) / 0.08 : 1
                    VStack(spacing: 0) {
                        LinearGradient(colors: [FAColor.forestSoft.opacity(0), FAColor.forestSoft.opacity(0.30)], startPoint: .top, endPoint: .bottom).frame(height: 34)
                        Rectangle().fill(FAColor.forestSoft).frame(height: 2).shadow(color: FAColor.forestSoft.opacity(0.9), radius: 8)
                        LinearGradient(colors: [FAColor.forestSoft.opacity(0.30), FAColor.forestSoft.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 34)
                    }
                    .frame(width: size)
                    .offset(y: -size / 2 + CGFloat(p) * size)
                    .opacity(opacity)
                }
            }
            Reticle(done: done)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
        .accessibilityLabel(String(localized: "capture.photo.a11y", defaultValue: "Your meal photo"))
    }
}

/// Describe path: no photo. The typed words with the same green scanning shimmer.
struct ReadingCanvas: View {
    let width: CGFloat
    let description: String
    let done: Bool

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [FAColor.forestSoft, FAColor.forestGlow], startPoint: .leading, endPoint: .trailing).frame(height: 6)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                    } else {
                        TimelineView(.animation) { context in
                            let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                            Circle().fill(FAColor.forestSoft).frame(width: 7, height: 7).opacity(0.3 + 0.7 * sin(raw * .pi))
                        }
                    }
                    Text((done ? String(localized: "capture.reading.got", defaultValue: "Got it") : String(localized: "capture.reading.words", defaultValue: "Reading your description")).uppercased())
                        .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(FAColor.forestSoft)
                }
                Text("“\(description)”").font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.charcoal).lineSpacing(6)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: width * 0.62, alignment: .leading)
            .overlay {
                if !done {
                    TimelineView(.animation) { context in
                        let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 1.7
                        LinearGradient(colors: [FAColor.forestSoft.opacity(0), FAColor.forestSoft.opacity(0.14), FAColor.forestSoft.opacity(0)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.5)
                            .offset(x: -width * 0.75 + CGFloat(raw) * width * 1.5)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
    }
}

/// Placeholder hero images for meals without a photo — the Expo bank (royalty-free Unsplash food
/// photography). The pick is hashed off the dish name so the same meal keeps the same illustration.
enum MealPlaceholderImage {
    private static func u(_ id: String) -> String { "https://images.unsplash.com/photo-\(id)?auto=format&fit=crop&w=900&q=60" }
    private static let bank: [MealLog.MealType: [String]] = [
        .breakfast: [u("1525351484163-7529414344d8"), u("1533089860892-a7c6f0a88666"), u("1484723091739-30a097e8f929")],
        .lunch: [u("1546069901-ba9599a7e63c"), u("1512621776951-a57141f2eefd"), u("1504674900247-0877df9cc836")],
        .dinner: [u("1467003909585-2f8a72700288"), u("1544025162-d76694265947"), u("1565299624946-b28f40a0ae38")],
        .snack: [u("1490474418585-ba9bad8fd0ea"), u("1482049016688-2d3e1b311543"), u("1565958011703-44f9829ba187")],
    ]

    static func url(mealType: MealLog.MealType?, dishName: String) -> URL? {
        let list = bank[mealType ?? .lunch] ?? bank[.lunch]!
        var hash: UInt32 = 0
        for c in dishName.unicodeScalars { hash = hash &* 31 &+ c.value }
        return URL(string: list[Int(hash % UInt32(list.count))])
    }
}
