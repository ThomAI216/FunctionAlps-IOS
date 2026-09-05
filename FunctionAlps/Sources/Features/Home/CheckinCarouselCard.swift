import SwiftUI

/// The Home check-in carousel: one glass card per moment (morning · midday · evening), each with its own
/// landscape at the top (sunrise / noon / sunset — `Media/checkin-<slot>.jpg`, a sky gradient until the
/// image lands), two glass chips floating on the picture (the streak, last night's sleep from Apple
/// Health), the moment's title and state below, and the CTA pill. Glass inside glass, like the owner's
/// reference booking card.
struct CheckinCarouselCard: View {
    let today: TodaySnapshot
    let now: MomentSlot
    let streak: Int
    /// Hours asleep last night (Apple Health, else the member's own morning answer); nil = unknown.
    let sleepHours: Double?
    @State private var page: MomentSlot

    init(today: TodaySnapshot, now: MomentSlot, streak: Int, sleepHours: Double?) {
        self.today = today
        self.now = now
        self.streak = streak
        self.sleepHours = sleepHours
        _page = State(initialValue: now)
    }

    var body: some View {
        FACard(padded: false) {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(MomentSlot.order, id: \.self) { slot in
                        NavigationLink(value: Route.checkin(slot)) {
                            CheckinSlotPage(slot: slot, isNow: slot == now, done: CheckinEngine.slotIsDone(today.moments, slot), streak: streak, sleepHours: sleepHours)
                        }
                        .buttonStyle(.plain)
                        .tag(slot)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 318)
                HStack(spacing: 6) {
                    ForEach(MomentSlot.order, id: \.self) { slot in
                        Capsule()
                            .fill(slot == page ? FAColor.ink.opacity(0.8) : FAColor.ink.opacity(0.22))
                            .frame(width: slot == page ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                    }
                }
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One page of the carousel.
private struct CheckinSlotPage: View {
    let slot: MomentSlot
    let isNow: Bool
    let done: Bool
    let streak: Int
    let sleepHours: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CheckinLandscape(slot: slot)
                HStack(spacing: 8) {
                    chip(symbol: "flame", text: streak > 0
                        ? String(localized: "home.streak.days", defaultValue: "\(streak)-day streak")
                        : String(localized: "home.streak.none", defaultValue: "Start a streak"))
                    chip(symbol: "moon.zzz", text: sleepText)
                }
                .padding(12)
            }
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(FAColor.ink).lineLimit(1).minimumScaleFactor(0.8)
                    Text(status).font(FATypography.sans(12.5, .medium, relativeTo: .caption)).foregroundStyle(done || isNow ? FAColor.accent : FAColor.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(cta)
                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.charcoal)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 14)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status)")
    }

    private var title: String {
        switch slot {
        case .morning: String(localized: "home.carousel.morning", defaultValue: "Morning check-in")
        case .midday: String(localized: "home.carousel.midday", defaultValue: "Midday check-in")
        case .evening: String(localized: "home.carousel.evening", defaultValue: "Evening check-in")
        }
    }

    private var status: String {
        if done { return String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust") }
        if isNow { return String(localized: "home.carousel.now", defaultValue: "It's time · about a minute") }
        switch slot {
        case .morning: return String(localized: "home.carousel.morning.sub", defaultValue: "Sleep, energy and how you woke up")
        case .midday: return String(localized: "home.carousel.midday.sub", defaultValue: "Energy, mood and focus so far")
        case .evening: return String(localized: "home.carousel.evening.sub", defaultValue: "How the day landed, before bed")
        }
    }

    private var cta: String {
        done ? String(localized: "home.carousel.adjust", defaultValue: "Adjust") : String(localized: "home.checkin.cta", defaultValue: "Check in")
    }

    private var sleepText: String {
        guard let sleepHours else { return String(localized: "home.sleep.unknown", defaultValue: "Sleep · —") }
        let total = Int((sleepHours * 60).rounded())
        return String(localized: "home.sleep.hours", defaultValue: "\(total / 60) h \(String(format: "%02d", total % 60)) slept")
    }

    /// The inner glass: white type on the picture, the same clear glass as the card itself.
    private func chip(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(text).font(FATypography.sans(12.5, .medium, relativeTo: .caption)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(FAGlassSurface(cornerRadius: 14))
    }
}

/// The landscape at the top of each page: the owner's photograph when bundled, else the slot's sky.
struct CheckinLandscape: View {
    let slot: MomentSlot

    var body: some View {
        GeometryReader { geo in
            if let image = Self.image(for: slot) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(sun)
                        .frame(width: geo.size.width * 0.28)
                        .blur(radius: 10)
                        .offset(x: geo.size.width * sunX, y: -geo.size.height * sunY)
                    ridge(width: geo.size.width, height: geo.size.height * 0.34, phase: 0.6, wobble: 0.55)
                        .offsetBy(dx: 0, dy: geo.size.height * 0.66)
                        .fill(ridgeBack)
                    ridge(width: geo.size.width, height: geo.size.height * 0.24, phase: 2.1, wobble: 0.7)
                        .offsetBy(dx: 0, dy: geo.size.height * 0.76)
                        .fill(ridgeFront)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// `checkin-morning.jpg` / `.png` / `.webp` in `Resources/Media`.
    static func image(for slot: MomentSlot) -> UIImage? {
        let name = "checkin-\(slot.rawValue)"
        for ext in ["jpg", "jpeg", "png", "webp"] {
            if let img = FAMedia.image(name, ext: ext) { return img }
        }
        return nil
    }

    private var sky: [Color] {
        switch slot {
        case .morning: [Color(hex: 0xF7CDA9), Color(hex: 0xE9A3A4), Color(hex: 0x9B8AB9)]
        case .midday: [Color(hex: 0x8FC3E6), Color(hex: 0xD3EAF3), Color(hex: 0x9CC9A6)]
        case .evening: [Color(hex: 0xF2A96A), Color(hex: 0xD8707C), Color(hex: 0x5B4B7A)]
        }
    }
    private var sun: Color {
        switch slot {
        case .morning: Color(hex: 0xFFE3B0, opacity: 0.9)
        case .midday: Color(hex: 0xFFFBE6, opacity: 0.95)
        case .evening: Color(hex: 0xFFB36B, opacity: 0.9)
        }
    }
    private var sunX: CGFloat { slot == .midday ? 0.28 : -0.22 }
    private var sunY: CGFloat { slot == .midday ? 0.62 : 0.36 }
    private var ridgeBack: Color {
        switch slot {
        case .morning: Color(hex: 0x6E5A73, opacity: 0.85)
        case .midday: Color(hex: 0x5D7F68, opacity: 0.8)
        case .evening: Color(hex: 0x4A3B5E, opacity: 0.9)
        }
    }
    private var ridgeFront: Color {
        switch slot {
        case .morning: Color(hex: 0x3F3446)
        case .midday: Color(hex: 0x3B5A46)
        case .evening: Color(hex: 0x2A2236)
        }
    }

    private func ridge(width: CGFloat, height: CGFloat, phase: Double, wobble: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: height))
        var x: CGFloat = 0
        while x <= width {
            let t = Double(x / max(1, width))
            let y = height * (0.55 - 0.35 * sin(t * .pi * 2.2 + phase) - 0.15 * sin(t * .pi * 5.3 * wobble + phase * 1.7))
            p.addLine(to: CGPoint(x: x, y: max(0, y)))
            x += 6
        }
        p.addLine(to: CGPoint(x: width, y: height))
        p.closeSubpath()
        return p
    }
}
