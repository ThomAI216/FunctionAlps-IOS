import SwiftUI

// The Home screen's cards, matching the web app's `app/(tabs)/index.tsx` and
// `lib/components/home/*` card for card.

/// Functional hero (web `index.tsx`): the crown ring with the server composite, 14 day bars from the
/// same composite series, and the three pillar lines.
struct FunctionalHeroCard: View {
    let today: TodaySnapshot
    static let green = Color(hex: 0x8FBF97)

    private var scores: MemberScores? { today.scores }
    private var value: Int? { scores?.composite.intScore }
    private var series: [Int?] { scores?.crownSeries ?? Array(repeating: nil, count: 14) }

    var body: some View {
        FACard {
            HStack(spacing: 16) {
                VStack(spacing: 12) {
                    ActivityRing(pct: Double(value ?? 0) / 100, color: Self.green) {
                        VStack(spacing: 1) {
                            Text(value.map(String.init) ?? "·")
                                .font(FATypography.display(32, relativeTo: .title))
                                .foregroundStyle(FAColor.ink)
                            Text(String(localized: "home.hero.functional", defaultValue: "Functional").uppercased())
                                .font(FATypography.sans(7.5, .bold, relativeTo: .caption2))
                                .tracking(1.2)
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                    DayBars(series: series)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(0)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(MemberScores.Pillar.allCases, id: \.self) { pillar in
                        markerLine(pillar.title, scores?.breakdown(pillar).intScore, Color(hex: pillar.tintHex))
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "home.hero.a11y", defaultValue: "Functional score \(value.map(String.init) ?? "not yet available")"))
    }

    private func markerLine(_ name: String, _ value: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(name.uppercased())
                    .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(FAColor.inkSecondary)
                Spacer()
                Text(value.map(String.init) ?? "·")
                    .font(FATypography.display(14, relativeTo: .caption))
                    .foregroundStyle(FAColor.ink)
            }
            HashedBar(color: color, pct: Double(value ?? 0) / 100, height: 7)
        }
    }
}

/// 14-day history as thin pastel-green vertical bars; sparse data grows from the centre.
struct DayBars: View {
    let series: [Int?]
    @State private var fill: Double = 0
    private let height: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(series.enumerated()), id: \.offset) { _, v in
                let has = v != nil
                let h: CGFloat = has ? max(7, CGFloat(max(0, min(100, v ?? 0))) / 100 * height * CGFloat(fill)) : 5
                Capsule()
                    .fill(FunctionalHeroCard.green)
                    .frame(width: 5, height: h)
                    .opacity(has ? 0.95 : 0.2)
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: height)
        .mountFill($fill)
        .accessibilityHidden(true)
    }
}

/// "Log a meal" square: the Food tab's scan story played once on arrival, then frozen.
struct MealScanCard: View {
    @State private var scan: CGFloat = 0
    @State private var beat: Double = 0
    private static let chips: [(name: String, kcal: String, top: CGFloat, left: CGFloat?, right: CGFloat?)] = [
        ("Avocado · 70 g", "112 kcal", 0.08, 12, nil),
        ("Salmon · 120 g", "250 kcal", 0.30, nil, 10),
        ("Rice · 90 g", "117 kcal", 0.52, 14, nil),
    ]
    private static let wheels: [(type: String, value: Int, color: Color)] = [
        ("inflammation", 72, FAColor.scoreInflammation), ("glycemic", 64, FAColor.scoreGlycemic), ("digestion", 81, FAColor.scoreDigestion),
    ]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let band = max(1, h * 0.42)
            ZStack(alignment: .bottom) {
                Color(hex: 0x1B1A17)
                if let plate = FAMedia.image("plate-demo", ext: "jpg") {
                    Image(uiImage: plate)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: h)
                        .clipped()
                }
                LinearGradient(colors: [Self.green(0), Self.green(0.22), Color.white.opacity(0.5), Self.green(0.22), Self.green(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -band * 1.07 + scan * h * 1.5)
                    .allowsHitTesting(false)
                ForEach(Array(Self.chips.enumerated()), id: \.offset) { i, chip in
                    HStack(spacing: 4) {
                        Text(chip.name).font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.charcoal)
                        if beat >= [6.3, 6.8, 7.3][i] {
                            Text(chip.kcal).font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forestSoft)
                        } else {
                            Capsule().fill(FAColor.inkMuted.opacity(0.35)).frame(width: 34, height: 6)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .popIn(beat >= [4.4, 4.9, 5.4][i])
                    .position(x: chip.left.map { $0 + 52 } ?? (geo.size.width - (chip.right ?? 0) - 52), y: h * chip.top + 12)
                }
                HStack(spacing: 11) {
                    ForEach(Array(Self.wheels.enumerated()), id: \.offset) { i, w in
                        ZStack {
                            Circle().fill(Color.white.opacity(0.95))
                            ScoreRing(value: w.value, label: "", color: w.color, verdict: "", compact: true)
                        }
                        .frame(width: 34, height: 34)
                        .popIn(beat >= [7.7, 8.0, 8.3][i])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, h * 0.66)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
                    .overlay(alignment: .bottom) {
                        HStack {
                            Text(String(localized: "home.logMeal", defaultValue: "Log a meal"))
                                .font(FATypography.display(17, relativeTo: .headline))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Text("›").font(FATypography.sans(16, .bold)).foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 14).padding(.bottom, 10)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .task {
            guard beat == 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 2.1)) { scan = 1 }
            for t in [4.4, 4.9, 5.4, 6.3, 6.8, 7.3, 7.7, 8.0, 8.3] {
                let wait = t - max(2.0, beat)
                if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
                beat = t
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "home.logMeal", defaultValue: "Log a meal"))
    }

    private static func green(_ o: Double) -> Color { Color(red: 143 / 255, green: 191 / 255, blue: 151 / 255, opacity: o) }
}

/// "Check-In" square: four marker lines draw themselves left → right, then today's real scores pop on.
struct CheckinPulseCard: View {
    struct Marker: Identifiable {
        let key: String
        let name: String
        let color: Color
        let value: Int?
        var id: String { key }
    }
    let markers: [Marker]
    @State private var progress: [Double] = [0, 0, 0, 0]
    @State private var beat: Double = 0

    private static let waves: [(amp: Double, base: Double, k: Double, phase: Double, opacity: Double)] = [
        (0.08, 0.40, 2.0, 0.0, 0.7), (0.10, 0.46, 1.4, 1.9, 0.65), (0.07, 0.52, 2.6, 3.6, 0.65), (0.09, 0.58, 1.8, 5.0, 0.6),
    ]
    private static let chipAt: [Double] = [2.3, 2.75, 3.2, 3.65]
    private static let chipTop: [CGFloat] = [0.10, 0.24, 0.42, 0.63]
    /// mood/sleep high above the wave band, energy just above it, calmness inside it — no clustering.
    private static func chipX(_ i: Int, width: CGFloat) -> CGFloat {
        switch i {
        case 0: 12 + 46
        case 1: width - 10 - 46
        case 2: 22 + 46
        default: width - 14 - 46
        }
    }

    var body: some View {
        FACard(padded: false) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .bottom) {
                    ForEach(0..<4, id: \.self) { i in
                        let def = Self.waves[i]
                        wave(w: w, h: h, def)
                            .trim(from: 0, to: progress[i])
                            .stroke((markers.indices.contains(i) ? markers[i].color : FAColor.forestSoft).opacity(def.opacity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    ForEach(Array(markers.prefix(4).enumerated()), id: \.offset) { i, m in
                        HStack(spacing: 5) {
                            Circle().fill(m.color).frame(width: 7, height: 7)
                            (Text(m.name + " ").font(FATypography.sans(10, .semibold, relativeTo: .caption2)) + Text(m.value.map(String.init) ?? "·").font(FATypography.sans(10, .bold, relativeTo: .caption2)))
                                .foregroundStyle(FAColor.charcoal)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .popIn(beat >= Self.chipAt[i])
                        .position(x: Self.chipX(i, width: w), y: h * Self.chipTop[i] + 12)
                    }
                    HStack {
                        Text(String(localized: "home.checkIn", defaultValue: "Check-In"))
                            .font(FATypography.display(17, relativeTo: .headline))
                            .foregroundStyle(FAColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text("›").font(FATypography.sans(16, .bold)).foregroundStyle(FAColor.inkSecondary)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
        }
        .task {
            guard beat == 0 else { return }
            for i in 0..<4 {
                let delay = [0.1, 0.5, 0.9, 1.3][i]
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 2.0)) { progress[i] = 1 }
                }
            }
            for t in Self.chipAt {
                let wait = t - beat
                if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
                beat = t
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "home.checkIn", defaultValue: "Check-In"))
    }

    private func wave(w: CGFloat, h: CGFloat, _ def: (amp: Double, base: Double, k: Double, phase: Double, opacity: Double)) -> Path {
        var path = Path()
        let width = Double(max(1, w))
        let height = Double(h)
        var x = 0.0
        while x <= width {
            let y = def.base * height + def.amp * height * sin(2 * Double.pi * def.k * x / width + def.phase)
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += 4
        }
        return path
    }
}

/// Home entry to the clinician thread — always rendered, the count is live.
struct MessagesCard: View {
    let unread: Int

    var body: some View {
        FACard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(red: 74 / 255, green: 138 / 255, blue: 92 / 255, opacity: 0.14))
                    Image(systemName: "bubble.left").foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unread > 0 ? String(localized: "home.messages.replied", defaultValue: "Your nutritionist replied") : String(localized: "home.messages.ask", defaultValue: "Ask your nutritionist"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline))
                        .foregroundStyle(FAColor.ink)
                    Text(unread > 0 ? String(localized: "home.messages.read", defaultValue: "Tap to read") : String(localized: "home.messages.human", defaultValue: "A real person answers"))
                        .font(FATypography.sans(13, relativeTo: .callout))
                        .foregroundStyle(FAColor.inkSecondary)
                }
                Spacer()
                if unread > 0 {
                    Text("\(unread)")
                        .font(FATypography.sans(12, .bold, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(FAColor.forestSoft, in: Capsule())
                }
                Image(systemName: "chevron.right").foregroundStyle(FAColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
