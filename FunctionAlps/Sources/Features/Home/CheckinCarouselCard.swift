import SwiftUI

/// The Home check-in carousel — two cards, morning and evening, where the owner's photograph IS the card
/// (full-bleed, rounded like the meal-scan card), with small glass panes floating on it: the morning card
/// carries last night's sleep (Apple Health) and the streak, the evening card the day's meals and moments.
/// Title, state line and the white CTA pill sit on a dark band at the foot of the picture.
struct CheckinCarouselCard: View {
    let today: TodaySnapshot
    let now: MomentSlot
    let streak: Int
    /// Hours asleep last night (Apple Health, else the member's own morning answer); nil = unknown.
    let sleepHours: Double?
    @State private var page: MomentSlot

    static let pages: [MomentSlot] = [.morning, .evening]

    init(today: TodaySnapshot, now: MomentSlot, streak: Int, sleepHours: Double?) {
        self.today = today
        self.now = now
        self.streak = streak
        self.sleepHours = sleepHours
        _page = State(initialValue: now == .evening ? .evening : .morning)
    }

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Self.pages, id: \.self) { slot in
                    NavigationLink(value: Route.checkin(slot)) {
                        CheckinSlotCard(slot: slot, today: today, isNow: slot == now, streak: streak, sleepHours: sleepHours)
                    }
                    .buttonStyle(.plain)
                    .tag(slot)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 300)
            HStack(spacing: 6) {
                ForEach(Self.pages, id: \.self) { slot in
                    Capsule()
                        .fill(slot == page ? FAColor.ink.opacity(0.75) : FAColor.ink.opacity(0.22))
                        .frame(width: slot == page ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One card: the photograph, the glass panes, the foot band.
private struct CheckinSlotCard: View {
    let slot: MomentSlot
    let today: TodaySnapshot
    let isNow: Bool
    let streak: Int
    let sleepHours: Double?

    private var done: Bool { CheckinEngine.slotIsDone(today.moments, slot) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CheckinLandscape(slot: slot)
            // A whisper of shade at the top so white type reads on a bright sky.
            LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 8) {
                switch slot {
                case .evening:
                    pane(symbol: "fork.knife", value: "\(today.meals.count)", label: today.meals.count == 1
                        ? String(localized: "home.pane.mealOne", defaultValue: "meal logged")
                        : String(localized: "home.pane.meals", defaultValue: "meals logged"))
                    pane(symbol: "checkmark.circle", value: "\(momentsDone)/\(MomentSlot.order.count)", label: String(localized: "home.pane.checkins", defaultValue: "check-ins today"))
                default:
                    pane(symbol: "moon.zzz", value: sleepValue, label: String(localized: "home.pane.slept", defaultValue: "slept last night"))
                    pane(symbol: "flame", value: "\(streak)", label: streak == 1
                        ? String(localized: "home.pane.streakOne", defaultValue: "day streak")
                        : String(localized: "home.pane.streak", defaultValue: "day streak"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.66)], startPoint: .top, endPoint: .bottom)
                .frame(height: 118)
                .overlay(alignment: .bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                            Text(status).font(FATypography.sans(12.5, .medium, relativeTo: .caption)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(done ? String(localized: "home.carousel.adjust", defaultValue: "Adjust") : String(localized: "home.checkin.cta", defaultValue: "Check in"))
                            .font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(FAColor.charcoal)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Color.white.opacity(0.94), in: Capsule())
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 14)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status)")
    }

    private var momentsDone: Int { MomentSlot.order.filter { CheckinEngine.slotIsDone(today.moments, $0) }.count }

    private var sleepValue: String {
        guard let sleepHours else { return "—" }
        let total = Int((sleepHours * 60).rounded())
        return "\(total / 60) h \(String(format: "%02d", total % 60))"
    }

    private var title: String {
        slot == .evening
            ? String(localized: "home.carousel.evening", defaultValue: "Evening check-in")
            : String(localized: "home.carousel.morning", defaultValue: "Morning check-in")
    }

    private var status: String {
        if done { return String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust") }
        if isNow { return String(localized: "home.carousel.now", defaultValue: "It's time · about a minute") }
        return slot == .evening
            ? String(localized: "home.carousel.evening.sub", defaultValue: "How the day landed, before bed")
            : String(localized: "home.carousel.morning.sub", defaultValue: "Sleep, energy and how you woke up")
    }

    /// A mini glass card on the photograph: a big number and its label.
    private func pane(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 18)
            Text(value).font(FATypography.display(20, relativeTo: .title3))
            Text(label).font(FATypography.sans(12, .medium, relativeTo: .caption)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .modifier(FAGlassSurface(cornerRadius: 16))
        .fixedSize()
    }
}

/// The photograph behind each card (`Media/checkin-<slot>.jpg`), a sky gradient only if the file is missing.
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
                LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

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
}
