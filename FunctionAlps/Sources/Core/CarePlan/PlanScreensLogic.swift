import Foundation

/// Pure shaping for the rebuilt client plan screens (CLINICAL 2026-11-12): the Home top card, My Plan, and the focus and
/// action detail pages. No clock and no view: every day is an explicit `YYYY-MM-DD`, and every word shown is the
/// practice's (rule 6). Colours are the decided palette (`decisions.md`, 2026-11-12): bloating brownish, iron reddish,
/// coffee bluish; actions orange-red, week's focus green, supplements blue, priorities greenish, wins gold.
enum PlanScreensLogic {
    // MARK: Palette

    enum Tint {
        static let forest: UInt32 = 0x2E5438
        static let focus: UInt32 = 0x4A8A5C
        static let actions: UInt32 = 0xD0603A
        static let supplements: UInt32 = 0x3F7FC4
        static let priorities: UInt32 = 0x6B9E78
        static let wins: UInt32 = 0xC48B35
        static let bloating: UInt32 = 0x8A5A3B
        static let iron: UInt32 = 0xC0453A
        static let coffee: UInt32 = 0x3F7FC4
        static let sleep: UInt32 = 0x7B61B8
        static let menopause: UInt32 = 0xDB2777
    }

    /// The colour a line belongs to, read from its words (a hypothesis title, a complaint name or signal key).
    /// Nothing matches = the brand forest: no colour is ever invented for a signal the palette does not know.
    static func signalHex(for text: String?) -> UInt32 {
        let key = (text ?? "").lowercased()
        if key.contains("bloat") || key.contains("gut") || key.contains("digest") || key.contains("fodmap") { return Tint.bloating }
        if key.contains("iron") || key.contains("energy") || key.contains("fatigue") || key.contains("crash") { return Tint.iron }
        if key.contains("coffee") || key.contains("caffeine") { return Tint.coffee }
        if key.contains("sleep") { return Tint.sleep }
        return Tint.forest
    }

    /// The band colour of a programme: menopause pink, the gut programme green, forest for any other kind.
    static func bandHex(kind: String?) -> UInt32 {
        switch kind {
        case "hormones_menopause": Tint.menopause
        case "digestion": Tint.focus
        default: Tint.forest
        }
    }

    // MARK: Week ticks (focus and action detail)

    struct WeekTick: Equatable, Sendable, Identifiable {
        let day: String
        let done: Bool
        var id: String { day }
    }

    /// Monday to Sunday of the week that holds `day`, as `YYYY-MM-DD`. An unparseable day gives an empty week.
    static func week(containing day: String) -> [String] {
        guard let weekday = HabitEngine.weekday(day) else { return [] }
        let mondayOffset = (weekday + 6) % 7 // Sunday = 0 in HabitEngine, so Monday = 0 here
        let monday = HabitEngine.shift(day, by: -mondayOffset)
        return (0..<7).map { HabitEngine.shift(monday, by: $0) }
    }

    /// Which days of this week the habit was done: the plan's completions for it, read against Monday to Sunday.
    static func weekTicks(habitId: String, completions: [HabitCompletionRow], today: String) -> [WeekTick] {
        let doneDays = Set(completions.filter { $0.habitId == habitId }.map(\.day))
        return week(containing: today).map { WeekTick(day: $0, done: doneDays.contains($0)) }
    }

    static func doneCount(_ ticks: [WeekTick]) -> Int { ticks.filter(\.done).count }

    // MARK: Resources

    /// The habit's links a member may open: titled entries with an http(s) address. Anything else is left out, so no
    /// link ever opens an app scheme or an unreadable address.
    static func links(_ habit: HabitRow) -> [HabitLinks.Entry] {
        (habit.resources?.entries ?? []).filter { entry in
            let title = (entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let url = webURL(entry.url) else { return false }
            return url.scheme == "http" || url.scheme == "https"
        }
    }

    /// The URL of a resource entry, or nil when it is not a usable address.
    static func webURL(_ raw: String?) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), url.host?.isEmpty == false else { return nil }
        return url
    }

    /// "Why it matters for you": the habit's own why, when it has one.
    static func why(_ habit: HabitRow) -> String? {
        let text = (habit.generalWhy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
