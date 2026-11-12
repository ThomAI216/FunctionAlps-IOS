import SwiftUI

/// The Home check-in square (right of the meal-scan square): the check-in of the moment — the MORNING one before 14:00,
/// the DAILY functional one from 14:00 (owner, 2026-11-12; `MomentSlot.current`). Digestion is answered inside the daily one. Thomas, 2026-11-06: no mountain photograph; the card
/// is glass, with the five marker curves drawing themselves across it and the five marker pills (mood · sleep ·
/// energy · calm · digestion) scattered over them, and the title at the foot. The whole card is the way in.
struct EveningCheckinCard: View {
    let today: TodaySnapshot
    let now: MomentSlot

    var body: some View {
        NavigationLink(value: Route.checkin(now)) {
            CheckinCurvesCard(today: today, now: now)
        }
        .buttonStyle(.plain)
    }
}

/// One glass card, sized by its parent (a square on Home).
private struct CheckinCurvesCard: View {
    let today: TodaySnapshot
    let now: MomentSlot

    private var done: Bool { today.isDone(now) }

    /// mood · sleep · energy · calmness · digestion — today's reads, each with its accent (the curve's colour), and
    /// where its pill sits on the card (fractions of the width and height), scattered rather than in rows.
    private var markers: [(name: String, color: Color, value: Int?, x: CGFloat, y: CGFloat)] {
        let c = today.checkin
        return [
            (String(localized: "marker.mood", defaultValue: "Mood"), Color(hex: 0xDB2777), c?.mood, 0.30, 0.13),
            (String(localized: "marker.sleep", defaultValue: "Sleep"), Color(hex: 0x6366F1), c?.sleep, 0.76, 0.27),
            (String(localized: "marker.energy", defaultValue: "Energy"), Color(hex: 0xD97706), c?.energy, 0.27, 0.42),
            (String(localized: "marker.calm", defaultValue: "Calmness"), Color(hex: 0xE11D48), c?.calmness, 0.70, 0.55),
            (String(localized: "marker.digestion", defaultValue: "Digestion"), PulseWaves.digestionGreen, c?.gutOverall, 0.36, 0.66),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                PulseWaves()
                    .frame(width: w, height: h * 0.62)
                    .offset(y: h * 0.10)
                    .allowsHitTesting(false)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, m in
                    markerPill(m).position(x: w * m.x, y: h * m.y)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(FATypography.display(15, relativeTo: .headline)).foregroundStyle(FAColor.ink).lineLimit(1).minimumScaleFactor(0.75)
                    Text(status).font(FATypography.sans(9.5, .medium, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(width: w - 22, alignment: .leading)
                .position(x: w / 2, y: h - 22)
            }
        }
        .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status)")
    }

    private var title: String {
        now == .morning
            ? String(localized: "home.carousel.morning", defaultValue: "Morning check-in")
            : String(localized: "home.carousel.evening", defaultValue: "Functional check-in")
    }

    private var status: String {
        if done { return String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust") }
        return now == .morning
            ? String(localized: "home.carousel.morning.feeling", defaultValue: "Your night and how you feel · about a minute")
            : String(localized: "home.carousel.daily.sub", defaultValue: "Your night and your day · about a minute")
    }

    /// One marker pill: its colour dot, the name and today's read (— until the check-in is done).
    private func markerPill(_ m: (name: String, color: Color, value: Int?, x: CGFloat, y: CGFloat)) -> some View {
        HStack(spacing: 4) {
            Circle().fill(m.color).frame(width: 5, height: 5)
            Text(m.name).font(FATypography.sans(8.5, .medium, relativeTo: .caption2))
            Text(m.value.map { "\($0)" } ?? "—").font(FATypography.display(9.5, relativeTo: .caption2))
        }
        .foregroundStyle(FAColor.ink)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(m.color.opacity(0.35), lineWidth: 0.75))
        .fixedSize()
    }
}

/// The five marker curves (mood · sleep · energy · calm · digestion) drawing themselves left → right — the old
/// Check-In square's pulse.
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
