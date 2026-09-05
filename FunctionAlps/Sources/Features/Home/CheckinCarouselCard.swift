import SwiftUI

/// The Home check-in square (right of the meal-scan square): a paged carousel of photo cards — morning
/// (sunrise), evening (sunset) and the gut check-in (the lake) — where the owner's photograph IS the
/// card. On each: the four marker curves drawing themselves across the picture (the old Check-In
/// square's pulse), small glass panes with the page's own numbers, and the title + white pill on a dark
/// foot band. Page dots in the top-right corner.
struct CheckinCarouselCard: View {
    enum Page: String, CaseIterable, Hashable {
        case morning, evening, gut
        var route: Route {
            switch self {
            case .morning: .checkin(.morning)
            case .evening: .checkin(.evening)
            case .gut: .gutCheckin
            }
        }
    }

    let today: TodaySnapshot
    let now: MomentSlot
    let streak: Int
    /// Hours asleep last night (Apple Health, else the member's own morning answer); nil = unknown.
    let sleepHours: Double?
    @State private var page: Page

    init(today: TodaySnapshot, now: MomentSlot, streak: Int, sleepHours: Double?) {
        self.today = today
        self.now = now
        self.streak = streak
        self.sleepHours = sleepHours
        _page = State(initialValue: now == .evening ? .evening : .morning)
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Page.allCases, id: \.self) { p in
                NavigationLink(value: p.route) {
                    CheckinPhotoCard(page: p, today: today, now: now, streak: streak, sleepHours: sleepHours)
                }
                .buttonStyle(.plain)
                .tag(p)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { p in
                    Capsule()
                        .fill(Color.white.opacity(p == page ? 0.95 : 0.45))
                        .frame(width: p == page ? 12 : 4, height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }
            .padding(10)
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
    }
}

/// One photo card, sized by its parent (a square on Home).
private struct CheckinPhotoCard: View {
    let page: CheckinCarouselCard.Page
    let today: TodaySnapshot
    let now: MomentSlot
    let streak: Int
    let sleepHours: Double?

    private var done: Bool {
        switch page {
        case .morning: CheckinEngine.slotIsDone(today.moments, .morning)
        case .evening: CheckinEngine.slotIsDone(today.moments, .evening)
        case .gut: today.checkin?.isGutDone ?? false
        }
    }
    private var isNow: Bool {
        switch page {
        case .morning: now == .morning
        case .evening: now == .evening
        case .gut: false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                CheckinLandscape(name: "checkin-\(page.rawValue)", fallback: sky)
                LinearGradient(colors: [.black.opacity(0.26), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.45)
                    .frame(maxHeight: .infinity, alignment: .top)
                PulseWaves()
                    .frame(height: h * 0.5)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: h * 0.06)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 5) {
                    switch page {
                    case .morning:
                        pane(symbol: "moon.zzz", value: sleepValue, label: String(localized: "home.pane.slept.short", defaultValue: "slept"))
                        pane(symbol: "flame", value: "\(streak)", label: streak == 1
                            ? String(localized: "home.pane.streakOne", defaultValue: "day streak")
                            : String(localized: "home.pane.streak", defaultValue: "day streak"))
                    case .evening:
                        pane(symbol: "fork.knife", value: "\(today.meals.count)", label: today.meals.count == 1
                            ? String(localized: "home.pane.mealOne", defaultValue: "meal logged")
                            : String(localized: "home.pane.meals", defaultValue: "meals logged"))
                        pane(symbol: "checkmark.circle", value: "\(momentsDone)/\(MomentSlot.order.count)", label: String(localized: "home.pane.checkins.short", defaultValue: "check-ins"))
                    case .gut:
                        pane(symbol: "waveform.path", value: today.checkin?.gutOverall.map { "\($0)" } ?? "—", label: String(localized: "home.pane.gutScore", defaultValue: "gut today"))
                        pane(symbol: "flame", value: "\(streak)", label: streak == 1
                            ? String(localized: "home.pane.streakOne", defaultValue: "day streak")
                            : String(localized: "home.pane.streak", defaultValue: "day streak"))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.42)
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title).font(FATypography.display(15, relativeTo: .headline)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                                Text(status).font(FATypography.sans(9.5, .medium, relativeTo: .caption2)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 4)
                            Text(done ? String(localized: "home.carousel.adjust", defaultValue: "Adjust") : String(localized: "home.checkin.cta", defaultValue: "Check in"))
                                .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2))
                                .foregroundStyle(FAColor.charcoal)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.white.opacity(0.94), in: Capsule())
                                .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                        }
                        .padding(.horizontal, 11).padding(.bottom, 10)
                    }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status)")
    }

    private var momentsDone: Int { MomentSlot.order.filter { CheckinEngine.slotIsDone(today.moments, $0) }.count }

    private var sleepValue: String {
        guard let sleepHours else { return "—" }
        let total = Int((sleepHours * 60).rounded())
        return "\(total / 60)h\(String(format: "%02d", total % 60))"
    }

    private var title: String {
        switch page {
        case .morning: String(localized: "home.carousel.morning", defaultValue: "Morning check-in")
        case .evening: String(localized: "home.carousel.evening", defaultValue: "Evening check-in")
        case .gut: String(localized: "home.gut.title", defaultValue: "Gut check-in")
        }
    }

    private var status: String {
        if done { return String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust") }
        if isNow { return String(localized: "home.carousel.now", defaultValue: "It's time · about a minute") }
        switch page {
        case .morning: return String(localized: "home.carousel.morning.sub", defaultValue: "Sleep, energy and how you woke up")
        case .evening: return String(localized: "home.carousel.evening.sub", defaultValue: "How the day landed, before bed")
        case .gut: return String(localized: "home.gut.sub.short", defaultValue: "Comfort, stool, food reactions")
        }
    }

    private var sky: [Color] {
        switch page {
        case .morning: [Color(hex: 0xF7CDA9), Color(hex: 0xE9A3A4), Color(hex: 0x9B8AB9)]
        case .evening: [Color(hex: 0xF2A96A), Color(hex: 0xD8707C), Color(hex: 0x5B4B7A)]
        case .gut: [Color(hex: 0x8FC3E6), Color(hex: 0xD3EAF3), Color(hex: 0x9CC9A6)]
        }
    }

    /// A small glass pane on the photograph: number + label, the same clear glass as every card.
    private func pane(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 11)
            Text(value).font(FATypography.display(12.5, relativeTo: .caption))
            Text(label).font(FATypography.sans(9, .medium, relativeTo: .caption2)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .modifier(FAGlassSurface(cornerRadius: 10))
        .fixedSize()
    }
}

/// The four marker curves (mood · sleep · energy · calm) drawing themselves left → right — the old
/// Check-In square's pulse, now over the photograph.
struct PulseWaves: View {
    @State private var progress: [Double] = [0, 0, 0, 0]
    private static let colors: [Color] = [Color(hex: 0xDB2777), Color(hex: 0x6366F1), Color(hex: 0xD97706), Color(hex: 0xE11D48)]
    private static let waves: [(amp: Double, base: Double, k: Double, phase: Double, opacity: Double)] = [
        (0.16, 0.40, 2.0, 0.0, 0.85), (0.20, 0.50, 1.4, 1.9, 0.8), (0.14, 0.60, 2.6, 3.6, 0.8), (0.18, 0.70, 1.8, 5.0, 0.75),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let def = Self.waves[i]
                    wave(w: geo.size.width, h: geo.size.height, def)
                        .trim(from: 0, to: progress[i])
                        .stroke(Self.colors[i].opacity(def.opacity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
            }
        }
        .task {
            guard progress == [0, 0, 0, 0] else { return }
            for i in 0..<4 {
                let delay = [0.1, 0.5, 0.9, 1.3][i]
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
