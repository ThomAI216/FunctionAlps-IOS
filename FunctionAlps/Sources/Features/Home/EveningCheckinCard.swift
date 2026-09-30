import SwiftUI

/// The Home check-in square (right of the meal-scan square): the evening check-in — the one check-in of the
/// day since 2026-09-30 (digestion is answered inside it) — where the owner's sunset photograph IS the card.
/// On it: the five marker curves drawing themselves across the picture, the five marker pills (mood · sleep ·
/// energy · calm · digestion) in glass, and the title on a dark foot band. The whole card is the way in.
struct EveningCheckinCard: View {
    let today: TodaySnapshot
    let now: MomentSlot

    var body: some View {
        NavigationLink(value: Route.checkin(.evening)) {
            CheckinPhotoCard(today: today, now: now)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
    }
}

/// One photo card, sized by its parent (a square on Home).
private struct CheckinPhotoCard: View {
    let today: TodaySnapshot
    let now: MomentSlot

    private var done: Bool { CheckinEngine.slotIsDone(today.moments, .evening) }
    private var isNow: Bool { now == .evening }

    /// mood · sleep · energy · calmness · digestion — today's reads, each with its accent (the curve's colour).
    private var markers: [(name: String, color: Color, value: Int?)] {
        let c = today.checkin
        return [
            (String(localized: "marker.mood", defaultValue: "Mood"), Color(hex: 0xDB2777), c?.mood),
            (String(localized: "marker.sleep", defaultValue: "Sleep"), Color(hex: 0x6366F1), c?.sleep),
            (String(localized: "marker.energy", defaultValue: "Energy"), Color(hex: 0xD97706), c?.energy),
            (String(localized: "marker.calm", defaultValue: "Calmness"), Color(hex: 0xE11D48), c?.calmness),
            (String(localized: "marker.digestion", defaultValue: "Digestion"), PulseWaves.digestionGreen, c?.gutOverall),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                CheckinLandscape(name: "checkin-evening", fallback: sky)
                LinearGradient(colors: [.black.opacity(0.26), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.45)
                    .frame(maxHeight: .infinity, alignment: .top)
                PulseWaves()
                    .frame(height: h * 0.5)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: h * 0.06)
                    .allowsHitTesting(false)
                // The five marker pills, just above the foot band.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { markerPill(markers[0]); markerPill(markers[1]) }
                    HStack(spacing: 4) { markerPill(markers[2]); markerPill(markers[3]) }
                    markerPill(markers[4])
                }
                .padding(.horizontal, 10)
                .padding(.bottom, h * 0.30)
                .frame(maxWidth: .infinity, alignment: .leading)

                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.42)
                    .overlay(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(FATypography.display(15, relativeTo: .headline)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                            Text(status).font(FATypography.sans(9.5, .medium, relativeTo: .caption2)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11).padding(.bottom, 10)
                    }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status)")
    }

    private var title: String { String(localized: "home.carousel.evening", defaultValue: "Evening check-in") }

    private var status: String {
        if done { return String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust") }
        if isNow { return String(localized: "home.carousel.now", defaultValue: "It's time · about a minute") }
        return String(localized: "home.carousel.evening.sub", defaultValue: "How the day landed, before bed")
    }

    private var sky: [Color] { [Color(hex: 0xF2A96A), Color(hex: 0xD8707C), Color(hex: 0x5B4B7A)] }

    /// One marker pill: its colour dot, the name and today's read (— until the check-in is done).
    private func markerPill(_ m: (name: String, color: Color, value: Int?)) -> some View {
        HStack(spacing: 4) {
            Circle().fill(m.color).frame(width: 5, height: 5)
            Text(m.name).font(FATypography.sans(8.5, .medium, relativeTo: .caption2))
            Text(m.value.map { "\($0)" } ?? "—").font(FATypography.display(9.5, relativeTo: .caption2))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .modifier(FAGlassSurface(cornerRadius: 8))
        .fixedSize()
    }
}

/// The five marker curves (mood · sleep · energy · calm · digestion) drawing themselves left → right — the old
/// Check-In square's pulse, now over the photograph.
struct PulseWaves: View {
    /// Digestion's accent — a clear green, set apart from the four warm/violet markers.
    static let digestionGreen = Color(hex: 0x22C55E)
    @State private var progress: [Double] = [0, 0, 0, 0, 0]
    private static let colors: [Color] = [Color(hex: 0xDB2777), Color(hex: 0x6366F1), Color(hex: 0xD97706), Color(hex: 0xE11D48), digestionGreen]
    private static let waves: [(amp: Double, base: Double, k: Double, phase: Double, opacity: Double)] = [
        (0.16, 0.40, 2.0, 0.0, 0.85), (0.20, 0.50, 1.4, 1.9, 0.8), (0.14, 0.60, 2.6, 3.6, 0.8), (0.18, 0.70, 1.8, 5.0, 0.75),
        (0.15, 0.55, 2.3, 2.7, 0.95),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Self.waves.count, id: \.self) { i in
                    let def = Self.waves[i]
                    wave(w: geo.size.width, h: geo.size.height, def)
                        .trim(from: 0, to: progress[i])
                        .stroke(Self.colors[i].opacity(def.opacity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
            }
        }
        .task {
            guard progress.allSatisfy({ $0 == 0 }) else { return }
            for i in 0..<Self.waves.count {
                let delay = [0.1, 0.5, 0.9, 1.3, 1.7][i]
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 2.0)) { progress[i] = 1 }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func wave(w: CGFloat, h: CGFloat, _ def: (amp: Double, base: Double, k: Double, phase: Double, opacity: Double)) -> Path {
        var path = Path()
        let width = Double(max(1, w)), height = Double(h)
        var x = 0.0
        while x <= width {
            let y = def.base * height + def.amp * height * sin(2 * Double.pi * def.k * x / width + def.phase)
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += 4
        }
        return path
    }
}

/// The photograph behind a card (`Media/<name>.jpg|jpeg|png|webp`), a sky gradient only if the file is missing.
struct CheckinLandscape: View {
    let name: String
    let fallback: [Color]

    var body: some View {
        GeometryReader { geo in
            if let image = Self.image(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                LinearGradient(colors: fallback, startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    static func image(named name: String) -> UIImage? {
        for ext in ["jpg", "jpeg", "png", "webp"] {
            if let img = FAMedia.image(name, ext: ext) { return img }
        }
        return nil
    }
}
