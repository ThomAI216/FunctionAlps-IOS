#if DEBUG
import Foundation

/// The habit screens as the showcase shows them (Thomas, 2026-11-10): the sample member "Marie" on a day of the Foundation
/// Track, her habits by moment of the day, their streaks, and a habit's page. The wording is the practice's own habit
/// copy (the approved mockup's `HABITS`, `MOVES`, and the titles of `ACTIONS`); the ticks are invented (mostly done,
/// one miss in five), like the mockup's. Nothing here is a real person; no network.
///
/// Scenes (`-FAShowcase <id>`):
///   `habits`       Home on day 8 at midday: the moment card, three new habits first, "3 more once these are done"
///   `habit-open`   the same, the first habit opened a little (description + "See the habit")
///   `habit-page`   the page of "Daylight first thing" on day 10, with its 14-day streak
///   `habit-first`  the page of "Protein at every meal" on its first day (day 8): no streak card
enum ShowcaseHabits {
    static var isOn: Bool {
        switch Showcase.screen {
        case .habits?, .habitOpen?, .habitPage?, .habitFirst?: true
        default: false
        }
    }

    static var defaultDay: Int? {
        switch Showcase.screen {
        case .habits?, .habitOpen?, .habitFirst?: 8
        case .habitPage?: 10
        default: nil
        }
    }

    /// The phone's hour in a habits scene (the shots are otherwise taken at 9:00): midday, where the pack is fullest.
    static var hourOverride: Int? {
        switch Showcase.screen {
        case .habits?, .habitOpen?: 12
        default: nil
        }
    }

    /// The row opened a little in `habit-open`.
    static var expandedKey: String? { Showcase.screen == .habitOpen ? "protein" : nil }

    static var pageKey: String { Showcase.screen == .habitFirst ? "protein" : "daylight" }

    // MARK: The habits

    private struct Habit {
        let key: String, title: String, moment: String, first: Int, last: Int?
        let summary: String, how: [String], benefits: [String], moves: [(String, String)], reads: [String]
        var video: (url: String, title: String)? = nil
    }

    private static let habits: [Habit] = [
        Habit(key: "daylight", title: "Daylight first thing: head out of the window, and breathe", moment: "morning", first: 4, last: nil,
              summary: "Right when you wake up: daylight and fresh air, before your phone.",
              how: ["Right when you wake up, before your phone", "Then 5 minutes outside, or at an open window", "No sunglasses; never look straight at the sun"],
              benefits: ["More awake in the morning", "Easier to fall asleep at night", "A steadier mood"],
              moves: [("Energy", "up"), ("Mood", "up"), ("Sleep", "up")], reads: ["light-sets-your-body-clock"]),
        Habit(key: "flow_5", title: "5-minute morning flow", moment: "morning", first: 7, last: 11,
              summary: "Five minutes inspired by qi gong: breathe with the arms, twist, shake it out.",
              how: ["Stand, feet hip-width apart", "Breathe with the arms, then twist side to side", "Shake it out"],
              benefits: ["Less stiffness in the morning", "More awake, sooner"],
              moves: [("Energy", "up"), ("Mood", "up"), ("Focus", "up")], reads: ["your-day-on-one-page"]),
        Habit(key: "mindful", title: "Mindful eating: no phone, chew, breathe, a glass of water", moment: "midday", first: 2, last: nil,
              summary: "No phone, chew a lot, breathe, a glass of water.",
              how: ["Phone away, screen off", "Chew each bite well; put the fork down between bites", "Three breaths before you start, a glass of water with the meal"],
              benefits: ["Lighter digestion, less bloating", "Full sooner, fewer cravings later", "Calmer meals"],
              moves: [("Digestion", "up"), ("Cravings", "down"), ("Stress", "down")], reads: ["mindful-eating"]),
        Habit(key: "breathing", title: "5 minutes of breathing, once a day", moment: "midday", first: 5, last: nil,
              summary: "5 minutes for yourself, once a day: deep breaths, a slow exhale, a hold.",
              how: ["Sit or lie down; never in water or while driving", "30 deep breaths, then breathe out slowly", "Hold as long as is comfortable; 2 rounds to start"],
              benefits: ["A calmer, clearer head", "Energy without coffee", "A moment that is yours"],
              moves: [("Stress", "down"), ("Focus", "up"), ("Energy", "up")], reads: ["breathe-the-time-you-give-yourself"],
              video: ("https://www.youtube.com/watch?v=nzCaZQqAs9I", "Guided breathing, with Wim Hof")),
        Habit(key: "snack_daily", title: "One exercise snack a day", moment: "midday", first: 7, last: 8,
              summary: "One exercise snack every day, no longer optional.",
              how: ["10 squats, or a minute up the stairs", "Any time you've been sitting a while"],
              benefits: ["Clarity of mind", "More energy"],
              moves: [("Focus", "up"), ("Energy", "up"), ("Mood", "up")], reads: ["exercise-snacks-foundation"]),
        Habit(key: "protein", title: "Protein at every meal", moment: "midday", first: 8, last: nil,
              summary: "A palm of protein at every meal.",
              how: ["Eggs, yogurt, fish, chicken, tofu, beans or lentils", "About the size of your palm", "Start with breakfast"],
              benefits: ["Fuller for longer", "Fewer cravings", "Keeping your muscle as you age"],
              moves: [("Cravings", "down"), ("Energy", "up")], reads: ["protein-at-every-meal-and-why-it-matters", "the-benefits-of-exercise-snacks"]),
        Habit(key: "carbs", title: "Complex carbs over refined", moment: "midday", first: 8, last: nil,
              summary: "Complex carbs rather than refined.",
              how: ["Whole grains, legumes, vegetables", "Fewer white-flour and sugary foods"],
              benefits: ["Steadier energy", "Fewer cravings"],
              moves: [("Energy", "up"), ("Focus", "up"), ("Cravings", "down")], reads: ["complex-or-refined-carbs-why-it-matters"]),
        Habit(key: "walk_meal", title: "A short walk after every meal", moment: "midday", first: 8, last: nil,
              summary: "A short walk after every meal.",
              how: ["Right after the meal, or within half an hour", "Easy pace, no sweat"],
              benefits: ["Steadier energy after meals", "Easier digestion"],
              moves: [("Energy", "up"), ("Digestion", "up")], reads: ["the-walk-after-every-meal"]),
        Habit(key: "caffeine", title: "No caffeine after 16:00", moment: "afternoon", first: 4, last: nil,
              summary: "Your last coffee, tea or energy drink before 16:00.",
              how: ["Coffee, black and green tea, cola and energy drinks all count", "After 16:00: decaf, herbal tea or water"],
              benefits: ["Falling asleep faster", "Deeper sleep"],
              moves: [("Sleep", "up"), ("Stress", "down")], reads: ["caffeine-and-your-sleep"]),
        Habit(key: "rule_321", title: "The 3-2-1 rule: 3 h no food, 2 h no intense exercise, 1 h no screens", moment: "evening", first: 4, last: nil,
              summary: "Before bed: 3 hours no food, 2 hours no intense exercise, 1 hour no screens.",
              how: ["3 hours before bed: your last food of the day", "2 hours before: no hard exercise. Stretching, light movement and a walk are fine",
                    "1 hour before: no scrolling. Answering a message is fine; it's the stimulating stuff you leave"],
              benefits: ["Falling asleep faster", "Waking less in the night", "Calmer evenings"],
              moves: [("Sleep", "up"), ("Energy", "up"), ("Stress", "down")], reads: ["the-3-2-1-rule", "your-evening-routine"]),
        Habit(key: "three_good", title: "Write down three good things about your day", moment: "evening", first: 5, last: 10,
              summary: "Write down three good things about your day.",
              how: ["In your phone or a journal", "Small things count"],
              benefits: ["A better mood", "A calmer evening"],
              moves: [("Mood", "up"), ("Stress", "down"), ("Sleep", "up")], reads: ["three-good-things"]),
        Habit(key: "book", title: "A book instead of a screen", moment: "evening", first: 10, last: nil,
              summary: "A book instead of a screen, in your last hour.",
              how: ["Put the phone in another room", "Read a few pages"],
              benefits: ["Sleepier at the right time", "Less noise in your head"],
              moves: [("Sleep", "up"), ("Stress", "down")], reads: ["your-evening-routine"]),
        Habit(key: "wind_down", title: "10 minutes to wind down: box breathing or NSDR", moment: "evening", first: 10, last: nil,
              summary: "10 minutes to let the day go: box breathing or an NSDR.",
              how: ["Lying down or sitting", "Box breathing, or follow the NSDR"],
              benefits: ["Falling asleep faster", "A calmer mind"],
              moves: [("Sleep", "up"), ("Stress", "down")], reads: ["nsdr-explained"],
              video: ("https://www.youtube.com/watch?v=KHIbgSN2qAU", "10-minute NSDR")),
    ]

    private static func running(_ h: Habit, on day: Int) -> Bool { h.first <= day && (h.last.map { day <= $0 } ?? true) }

    // MARK: Served to the backend

    static let days: [TrackDay] = {
        let base = ShowcaseTrack.days.isEmpty ? (1...14).map { TrackDay(day: $0, titleEn: "Day \($0)") } : ShowcaseTrack.days
        return base.map { day in
            var d = day
            d.actions = habits.filter { running($0, on: day.day) }.map { h in
                var a = TrackAction(key: h.key, moment: h.moment == "morning" ? .morning : h.moment == "evening" ? .evening : h.moment == "midday" ? .midday : .day)
                a.momentV2 = h.moment
                a.habitBankId = "habit-\(h.key)"
                a.isNew = h.first == day.day
                a.howEn = h.summary
                a.reads = h.reads
                return a
            }
            return d
        }
    }()

    static let cards: [ActionCardRow] = habits.map { h in
        var card = ActionCardRow(id: "habit-\(h.key)", title: h.title)
        card.description = h.summary
        card.howMd = h.how.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        card.defaultSlot = h.moment == "afternoon" ? nil : h.moment
        var raw: [ActionCardRow.RawLink] = []
        if let video = h.video { raw.append(.init(kind: "video", url: video.url, title: video.title, source: "youtube")) }
        raw += h.reads.prefix(2).map { .init(kind: "article", slug: $0, title: nil) }
        raw.append(.init(kind: "benefits", items: h.benefits.map { .init(label: $0) }))
        raw.append(.init(kind: "moves", items: h.moves.map { .init(label: $0.0, dir: $0.1) }))
        raw.append(.init(kind: "recipe", title: "A kind this build does not know"))
        card.resources = raw
        return card
    }

    /// Marie's ticks: each habit done on most of its days (one miss in five, as the mockup draws it); today, the morning ones.
    static func activity() -> [TrackActivityItem] {
        let today = min(ShowcaseTrack.day, 14)
        var items: [TrackActivityItem] = []
        for h in habits {
            let seed = h.key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            for day in h.first...max(h.first, today) where running(h, on: day) && day <= today {
                let done = day == today ? h.moment == "morning" && !(h.first == today) : (day * 7 + seed) % 5 != 0
                if done { items.append(TrackActivityItem(day: day, kind: .action, itemKey: h.key)) }
            }
        }
        return items
    }
}
#endif
