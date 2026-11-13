import Foundation

// The Trends page's arithmetic — owner-validated mockup v2 (2026-11-10). Everything here COUNTS, AVERAGES and
// FORMATS the member's own logs; it never scores or interprets them (CLAUDE.md rule 9). The only judgement is
// `TrendSentence`, a closed set of owner-approved lines. Pure: explicit `YYYY-MM-DD` days, no clock, no I/O.

/// The six signals, in the order the page lists them. Sleep leads: the night is the freshest read.
enum TrendSignal: String, CaseIterable, Sendable, Hashable, Identifiable {
    case sleep, energy, focus, mood, stress, digestion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: String(localized: "trends.signal.sleep", defaultValue: "Sleep")
        case .energy: String(localized: "trends.signal.energy", defaultValue: "Energy")
        case .focus: String(localized: "trends.signal.focus", defaultValue: "Focus")
        case .mood: String(localized: "trends.signal.mood", defaultValue: "Mood")
        case .stress: String(localized: "trends.signal.stress", defaultValue: "Stress")
        case .digestion: String(localized: "trends.signal.digestion", defaultValue: "Digestion")
        }
    }

    /// One colour per signal, the mockup's.
    var tintHex: UInt32 {
        switch self {
        case .sleep: 0x6366F1
        case .energy: 0xD97706
        case .focus: 0x4F86C6
        case .mood: 0xDB2777
        case .stress: 0xE11D48
        case .digestion: 0x22C55E
        }
    }

    /// The stored marker for stress is CALMNESS (higher = better); the member reads a stress LEVEL.
    var isStress: Bool { self == .stress }
}

/// The window control: 7 / 14 / 28 days, ending today. Each read also fetches the window before it.
enum TrendWindow: Int, CaseIterable, Sendable, Hashable, Identifiable {
    case week = 7, fortnight = 14, month = 28

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { String(localized: "trends.window.days", defaultValue: "\(rawValue) days") }

    /// Today's window plus the one before it, for the "previous N days" figures.
    static let readDays = 56
}

/// Every read the page needs, as the backend gave it — the input to `TrendsEngine.page`.
struct TrendsRaw: Sendable, Equatable {
    var today: String
    var checkins: [DailyCheckin] = []
    /// `patient_checkin_moments` by day — the focus read, the pills and the check-in's own sleep clock.
    var momentsByDay: [String: [CheckinMoment]] = [:]
    var gutDays: [GutDay] = []
    var plan: HabitPlan? = nil
    var supplementNames: [String] = []
    var meals: [MealLog] = []
    var reactions: [String: MealReaction] = [:]
    /// One assembled night per day (the richest source wins — `WearableNightAssembler`).
    var nights: [WearableNight] = []
    var wearableRows: [WearableLabeledRow] = []
    var vendorAccounts: [WearableVendorAccountRow] = []
    var appleHealthConnected = false
    var appleHealthLastSync: Date? = nil
    /// Clinician-validated rows only (RLS).
    var patterns: [UserPattern] = []

    var hasAnyLog: Bool { !checkins.isEmpty || !momentsByDay.isEmpty || !meals.isEmpty }
}

enum TrendsEngine {
    // MARK: Supplements, day by day

    /// One supplement's ticks over the Trends window, from the server's `observance.strip` (`member_supplements`; the strip
    /// covers 14 days, oldest first, so a 28-day window shows the last 14). Counts only; the server decides what was due.
    struct SupplementRow: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let days: [Supplement.StripDay]
        /// Days where everything due was taken, of the days due and over (today still to take is not counted).
        let taken: Int
        let due: Int
    }

    /// Active supplements that carry a strip, in the plan's order. Empty when the member has none (the card keeps its empty state).
    static func supplementRows(_ supplements: [Supplement], window: TrendWindow) -> [SupplementRow] {
        SupplementLogic.planOrder(supplements).filter(\.isActive).compactMap { s in
            guard let strip = s.observance?.strip, !strip.isEmpty else { return nil }
            let days = Array(strip.suffix(window.days))
            let marks = days.map(SupplementLogic.mark)
            let due = marks.filter { $0 == .taken || $0 == .partial || $0 == .missed }.count
            return SupplementRow(id: s.id, name: s.name, days: days, taken: marks.filter { $0 == .taken }.count, due: due)
        }
    }

    // MARK: Windows

    /// The window's days, oldest first, ending on `today`.
    static func days(_ window: TrendWindow, today: String) -> [String] {
        (0..<window.days).reversed().map { HabitEngine.shift(today, by: -$0) }
    }

    /// The `window.days` days before the window, oldest first.
    static func previousDays(_ window: TrendWindow, today: String) -> [String] {
        (window.days..<(window.days * 2)).reversed().map { HabitEngine.shift(today, by: -$0) }
    }

    static func mean(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    /// A previous-window figure needs at least this many logged days to mean anything.
    static let previousMinimum = 3
    static func previousMean(_ values: [Double?]) -> Double? {
        values.compactMap { $0 }.count >= previousMinimum ? mean(values) : nil
    }

    // MARK: Markers

    /// The daily rows and moments, indexed by day.
    struct Index: Sendable, Equatable {
        let checkins: [String: DailyCheckin]
        let moments: [String: [CheckinMoment]]

        init(_ raw: TrendsRaw) {
            checkins = Dictionary(raw.checkins.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
            moments = raw.momentsByDay
        }
    }

    /// The moments of a day, the latest slot first — the evening check-in is the day's read.
    static func latestFirst(_ moments: [CheckinMoment]?) -> [CheckinMoment] {
        (moments ?? []).sorted { $0.slot.rank > $1.slot.rank }
    }

    /// A signal's 0–100 marker for a day, HIGHER = BETTER. Stress is calmness here, exactly as stored — it is
    /// converted to a level only when it is shown (`level`). Focus is the mind half of the energy read, which
    /// only the moments carry.
    static func marker(_ signal: TrendSignal, on day: String, in index: Index) -> Double? {
        let row = index.checkins[day]
        let value: Int?
        switch signal {
        case .sleep: value = row?.sleep
        case .energy: value = row?.energy
        case .mood: value = row?.mood
        case .stress: value = row?.calmness
        case .digestion: value = row?.gutOverall
        case .focus: value = latestFirst(index.moments[day]).compactMap(\.energyMind).first
        }
        return value.map(Double.init)
    }

    /// 0–10 as the member reads it. Stress becomes a LEVEL: `10 − calm/10`.
    static func level(_ signal: TrendSignal, marker: Double) -> Double {
        let clamped = max(0, min(100, marker))
        return signal.isStress ? 10 - clamped / 10 : clamped / 10
    }

    /// The five words of the check-in's own slider for a 0–100 read (index as `FunctionalSliderView` rounds it).
    static func word(_ signal: TrendSignal, marker: Double) -> String? {
        let slider: SliderSpec?
        switch signal {
        case .sleep: slider = FunctionalSchema.sleep.sliders.first
        case .energy: slider = FunctionalSchema.energy.sliders.first { $0.key == "body" }
        case .focus: slider = FunctionalSchema.energy.sliders.first { $0.key == "mind" }
        case .mood: slider = FunctionalSchema.mood.sliders.first
        case .stress: slider = FunctionalSchema.stress.sliders.first
        case .digestion: slider = GutSchema.comfort.slider
        }
        guard let words = slider?.words else { return nil }
        let idx = Int((min(100, max(0, marker)) / 100 * 4).rounded())
        return words.indices.contains(idx) ? words[idx] : nil
    }

    // MARK: Series

    struct Series: Sendable, Equatable {
        let signal: TrendSignal
        let days: [String]
        /// 0–100, higher = better, nil = not logged that day.
        let values: [Double?]
        let previousValues: [Double?]

        var average: Double? { TrendsEngine.mean(values) }
        var previousAverage: Double? { TrendsEngine.previousMean(previousValues) }
        var loggedDays: Int { values.compactMap { $0 }.count }
        /// The newest logged day's marker.
        var latest: Double? { values.last(where: { $0 != nil }) ?? nil }
        var latestDay: String? {
            guard let i = values.lastIndex(where: { $0 != nil }) else { return nil }
            return days[i]
        }
        /// The same values as the member reads them, 0–10 (stress as a level).
        var levels: [Double?] { values.map { $0.map { TrendsEngine.level(signal, marker: $0) } } }
        var averageLevel: Double? { average.map { TrendsEngine.level(signal, marker: $0) } }
        var previousAverageLevel: Double? { previousAverage.map { TrendsEngine.level(signal, marker: $0) } }
        var latestLevel: Double? { latest.map { TrendsEngine.level(signal, marker: $0) } }
    }

    static func series(_ signal: TrendSignal, window: TrendWindow, today: String, index: Index) -> Series {
        let now = days(window, today: today)
        let before = previousDays(window, today: today)
        return Series(
            signal: signal, days: now,
            values: now.map { marker(signal, on: $0, in: index) },
            previousValues: before.map { marker(signal, on: $0, in: index) }
        )
    }

    // MARK: The functional score — EQUAL weight, mean of the signals that were logged that day

    /// A day's score on 0–100: the plain mean of the available signals' markers (stress as calm). Nil when none.
    static func score(on day: String, in index: Index) -> Double? {
        mean(TrendSignal.allCases.map { marker($0, on: day, in: index) })
    }

    struct Chip: Sendable, Equatable, Identifiable {
        let signal: TrendSignal
        /// That day's marker as it counts towards the score (0–100; stress as calm).
        let marker: Double?
        var id: TrendSignal { signal }
    }

    struct Score: Sendable, Equatable {
        /// The newest day in the window that has any signal.
        let day: String?
        let value: Int?
        let chips: [Chip]
        /// The score of each window day.
        let values: [Double?]
        let average: Double?
        let previousAverage: Double?
    }

    static func scoreSummary(window: TrendWindow, today: String, index: Index) -> Score {
        let now = days(window, today: today)
        let before = previousDays(window, today: today)
        let values = now.map { score(on: $0, in: index) }
        let latestIndex = values.lastIndex(where: { $0 != nil })
        let day = latestIndex.map { now[$0] }
        let chips = TrendSignal.allCases.map { signal in Chip(signal: signal, marker: day.flatMap { marker(signal, on: $0, in: index) }) }
        return Score(
            day: day,
            value: latestIndex.flatMap { values[$0] }.map { Int($0.rounded()) },
            chips: chips, values: values,
            average: mean(values),
            previousAverage: previousMean(before.map { score(on: $0, in: index) })
        )
    }

    // MARK: The plan, day by day

    struct PlanDay: Sendable, Equatable, Identifiable {
        let day: String
        let due: Int
        let done: Int
        var id: String { day }
    }

    struct Adherence: Sendable, Equatable {
        let days: [PlanDay]
        var due: Int { days.reduce(0) { $0 + $1.due } }
        var done: Int { days.reduce(0) { $0 + $1.done } }
        var maxDue: Int { days.map(\.due).max() ?? 0 }
    }

    /// Per window day: the active habits that were due (their RRULE, from the day they existed) and how many of
    /// those carry a completion that day. The same arithmetic Home's card uses (`HabitEngine.isDue`).
    static func adherence(plan: HabitPlan?, window: TrendWindow, today: String) -> Adherence {
        let windowDays = days(window, today: today)
        guard let plan else { return Adherence(days: windowDays.map { PlanDay(day: $0, due: 0, done: 0) }) }
        var doneByDay: [String: Set<String>] = [:]
        for c in plan.completions { doneByDay[c.day, default: []].insert(c.habitId) }
        let out = windowDays.map { day -> PlanDay in
            let due = plan.activeHabits.filter { HabitEngine.isDue($0.frequencyRule, on: day, start: $0.createdDay) }
            let done = due.filter { doneByDay[day]?.contains($0.id) == true }.count
            return PlanDay(day: day, due: due.count, done: done)
        }
        return Adherence(days: out)
    }

    // MARK: Devices

    static let appleHealthKey = "apple_health"

    struct Device: Sendable, Equatable, Identifiable {
        let key: String
        let name: String
        let sourceId: Int
        let lastSync: Date?
        var isAppleHealth: Bool { key == TrendsEngine.appleHealthKey }
        var id: String { key }
    }

    /// Apple Health on this phone when connected, then each live vendor account.
    static func devices(_ raw: TrendsRaw) -> [Device] {
        var out: [Device] = []
        if raw.appleHealthConnected {
            out.append(Device(key: appleHealthKey, name: String(localized: "source.appleHealth", defaultValue: "Apple Health"),
                              sourceId: WearableSource.appleHealth, lastSync: raw.appleHealthLastSync))
        }
        for account in raw.vendorAccounts where account.isLive {
            let vendor = WearableVendor.vendor(account.vendor)
            out.append(Device(key: account.vendor, name: vendor?.name ?? account.vendor.capitalized,
                              sourceId: vendor?.sourceId ?? 0, lastSync: account.lastSuccessfulSyncAt))
        }
        return out
    }

    // MARK: Food, day by day

    struct FoodMeal: Sendable, Equatable, Identifiable {
        let id: String
        let time: Date
        let name: String
        let photoPath: String?
        /// The member's own reaction words; empty = none logged.
        let words: [String]
        /// One tone per word, same order — the pill colour. Short or empty = grey.
        var tones: [ReactionTone] = []
    }

    struct FoodDay: Sendable, Equatable, Identifiable {
        let day: String
        let meals: [FoodMeal]
        var id: String { day }
    }

    /// "Sat well" / "A bit off" / "Rough" from how the meal sat, then the flags the member ticked. No scores.
    /// Each word carries a tone classified from the stored key, not the localised label.
    static func reactionItems(_ reaction: MealReaction?) -> [(word: String, tone: ReactionTone)] {
        guard let reaction else { return [] }
        var out: [(word: String, tone: ReactionTone)] = []
        switch reaction.sentiment {
        case .good: out.append((String(localized: "meal.felt.good", defaultValue: "Sat well"), .positive))
        case .watch: out.append((String(localized: "meal.felt.watch", defaultValue: "A bit off"), .mild))
        case .bad: out.append((String(localized: "meal.felt.bad", defaultValue: "Rough"), .strong))
        case nil: break
        }
        let flags = reaction.flags.filter { $0 != "overall_off" && $0 != "overall_rough" }.prefix(3)
        for flag in flags {
            let label = flag.replacingOccurrences(of: "_", with: " ")
            if !out.contains(where: { $0.word == label }) { out.append((label, ReactionTone.tone(for: flag))) }
        }
        return out
    }

    static func reactionWords(_ reaction: MealReaction?) -> [String] { reactionItems(reaction).map(\.word) }

    static func foodMeal(_ meal: MealLog, reactions: [String: MealReaction]) -> FoodMeal {
        let items = reactionItems(reactions[meal.id])
        return FoodMeal(id: meal.id, time: meal.loggedAt, name: meal.displayName, photoPath: meal.photoPath,
                        words: items.map(\.word), tones: items.map(\.tone))
    }

    /// Meals of the given days grouped by day, newest day first, each day's meals in the order they were eaten.
    static func foodDays(meals: [MealLog], reactions: [String: MealReaction], days: [String], calendar: Calendar) -> [FoodDay] {
        let wanted = Set(days)
        var byDay: [String: [MealLog]] = [:]
        for meal in meals {
            let day = ISO8601.dayString(meal.loggedAt, calendar: calendar)
            if wanted.contains(day) { byDay[day, default: []].append(meal) }
        }
        return byDay.keys.sorted(by: >).map { day in
            FoodDay(day: day, meals: (byDay[day] ?? []).sorted { $0.loggedAt < $1.loggedAt }.map { foodMeal($0, reactions: reactions) })
        }
    }

    // MARK: Pills — what the member ticked that day, in the check-in's own words

    /// The words a day's check-in pills give one signal. Energy and focus share the energy questions and the
    /// day's "what fuelled / drained you" catalogue; sleep adds the catalogue pills that belong to sleep.
    /// Stored-not-scored context: shown back as the member wrote it, never read as a health signal.
    static func pillWords(_ signal: TrendSignal, moments: [CheckinMoment]?) -> [String] {
        var out: [String] = []
        func add(_ label: String) { if !out.contains(label) { out.append(label) } }
        let dim: DimKey?
        switch signal {
        case .sleep: dim = .sleep
        case .energy, .focus: dim = .energy
        case .mood: dim = .mood
        case .stress: dim = .stress
        case .digestion: dim = nil
        }
        for moment in latestFirst(moments) {
            if let dim {
                for module in FunctionalSchema.spec(dim).pills where !PillCatalog.ownedGroups.contains(module.key) {
                    for key in moment.pills[module.key] ?? [] {
                        if let label = module.options.first(where: { $0.key == key })?.label { add(label) }
                    }
                }
            }
            if signal == .energy || signal == .focus || signal == .sleep {
                for group in [PillGroup.fuelled.rawValue, PillGroup.drained.rawValue] {
                    for key in moment.pills[group] ?? [] {
                        guard let pill = PillCatalog.pill(key) else { continue }
                        if signal == .sleep && pill.pillar != .sleep { continue }
                        add(pill.label)
                    }
                }
            }
        }
        return out
    }

    struct DayRow: Sendable, Equatable, Identifiable {
        let day: String
        let marker: Double
        let word: String?
        let pills: [String]
        var id: String { day }
    }

    /// The window's logged days of one signal, newest first, each with its word and that day's pills.
    static func dayRows(_ series: Series, index: Index) -> [DayRow] {
        series.days.indices.reversed().compactMap { i -> DayRow? in
            guard let marker = series.values[i] else { return nil }
            let day = series.days[i]
            return DayRow(day: day, marker: marker, word: word(series.signal, marker: marker),
                          pills: pillWords(series.signal, moments: index.moments[day]))
        }
    }

    // MARK: Sleep

    struct SleepEntry: Sendable, Equatable, Identifiable {
        let day: String
        let bedTime: String?
        let wakeTime: String?
        let inBedMin: Int?
        let asleepMin: Int?
        /// `0` · `1_2` · `3plus` — the bands the check-in and the wearables share.
        let wakeBand: String?
        let source: String
        let fromDevice: Bool
        var id: String { day }
        /// What the chart and the headline count: time asleep when a device measured it, else the check-in's length of night.
        var minutes: Int? { asleepMin ?? inBedMin }
    }

    struct SleepSummary: Sendable, Equatable {
        /// Per window day, oldest first (nil = no night for that day).
        let entries: [SleepEntry?]
        let previousEntries: [SleepEntry?]
        let days: [String]
        /// Refreshed 0–100 from the newest check-in that answered it, and its day.
        let refreshed: (day: String, value: Int)?
        /// When the newest night's source last synced.
        let updatedAt: Date?

        static func == (a: SleepSummary, b: SleepSummary) -> Bool {
            a.entries == b.entries && a.previousEntries == b.previousEntries && a.days == b.days
                && a.refreshed?.day == b.refreshed?.day && a.refreshed?.value == b.refreshed?.value && a.updatedAt == b.updatedAt
        }

        var hours: [Double?] { entries.map { $0?.minutes.map { Double($0) / 60 } } }
        var previousHours: [Double?] { previousEntries.map { $0?.minutes.map { Double($0) / 60 } } }
        var latest: SleepEntry? { entries.last(where: { $0 != nil }) ?? nil }
        var averageHours: Double? { TrendsEngine.mean(hours) }
        var previousAverageHours: Double? { TrendsEngine.previousMean(previousHours) }
        var hasNights: Bool { entries.contains { $0 != nil } }
        /// Newest first, for the table.
        var recent: [SleepEntry] { entries.compactMap { $0 }.reversed() }
    }

    /// One night per day: a device's when there is one, else what the member wrote in the check-in.
    static func sleepEntry(day: String, nights: [String: WearableNight], moments: [CheckinMoment]?) -> SleepEntry? {
        if let night = nights[day] {
            return SleepEntry(day: day, bedTime: night.bedTime, wakeTime: night.wakeTime, inBedMin: night.durationMin,
                              asleepMin: night.asleepMin, wakeBand: night.wakeCount,
                              source: WearableVendor.sourceName(night.sourceId), fromDevice: true)
        }
        guard let m = latestFirst(moments).first(where: { $0.hasSleep && ($0.sleepDurationMin != nil || $0.sleepBedTime != nil || $0.sleepWakeTime != nil) }) else { return nil }
        return SleepEntry(day: day, bedTime: m.sleepBedTime, wakeTime: m.sleepWakeTime, inBedMin: m.sleepDurationMin, asleepMin: nil,
                          wakeBand: m.sleepWakeCount, source: String(localized: "trends.source.checkin", defaultValue: "Check-in"), fromDevice: false)
    }

    static func sleepSummary(_ raw: TrendsRaw, window: TrendWindow) -> SleepSummary {
        let now = days(window, today: raw.today)
        let before = previousDays(window, today: raw.today)
        let nights = Dictionary(raw.nights.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
        func entry(_ day: String) -> SleepEntry? { sleepEntry(day: day, nights: nights, moments: raw.momentsByDay[day]) }
        let entries = now.map(entry)
        var refreshed: (day: String, value: Int)?
        for day in now.reversed() {
            if let v = latestFirst(raw.momentsByDay[day]).compactMap(\.sleepRefreshed).first { refreshed = (day, v); break }
        }
        // The freshness of the newest night: the vendor account (or this phone) that filed it.
        var updatedAt: Date?
        if let latest = entries.last(where: { $0 != nil }) ?? nil, latest.fromDevice, let night = nights[latest.day] {
            if night.sourceId == WearableSource.appleHealth {
                updatedAt = raw.appleHealthLastSync
            } else if let vendor = WearableVendor.all.first(where: { $0.sourceId == night.sourceId }) {
                updatedAt = raw.vendorAccounts.first { $0.vendor == vendor.key }?.lastSuccessfulSyncAt
            }
        }
        return SleepSummary(entries: entries, previousEntries: before.map(entry), days: now, refreshed: refreshed, updatedAt: updatedAt)
    }

    // MARK: Digestion

    struct DigestionDay: Sendable, Equatable, Identifiable {
        let day: String
        /// 0–100: the comfort read when logged, else the day's gut overall.
        let headline: Double?
        let headlineIsComfort: Bool
        let stoolFrequency: Int?
        let bristol: Int?
        let symptoms: [String]
        let meals: [FoodMeal]
        var id: String { day }
    }

    /// The label of a ticked gut symptom, in the gut check-in's own words.
    static func symptomLabel(_ key: String) -> String {
        let module = GutSchema.comfort.pills.first { $0.key == "symptoms" }
        return module?.options.first { $0.key == key }?.label ?? key.replacingOccurrences(of: "_", with: " ")
    }

    /// Newest first: comfort /10, stool (times · Bristol type), the symptoms ticked, every meal with its reaction words.
    static func digestionDays(_ raw: TrendsRaw, window: TrendWindow, calendar: Calendar) -> [DigestionDay] {
        let windowDays = days(window, today: raw.today)
        let gut = Dictionary(raw.gutDays.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
        let checkins = Dictionary(raw.checkins.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
        let food = Dictionary(foodDays(meals: raw.meals, reactions: raw.reactions, days: windowDays, calendar: calendar).map { ($0.day, $0.meals) },
                              uniquingKeysWith: { _, later in later })
        return windowDays.reversed().compactMap { day -> DigestionDay? in
            let g = gut[day]
            let overall = checkins[day]?.gutOverall.map(Double.init) ?? g?.overall.map(Double.init)
            let comfort = g?.comfort.map(Double.init)
            let meals = food[day] ?? []
            let symptoms = (g?.symptoms ?? []).map(symptomLabel)
            if overall == nil && comfort == nil && g?.stoolFrequency == nil && g?.bristol == nil && symptoms.isEmpty && meals.isEmpty { return nil }
            return DigestionDay(day: day, headline: comfort ?? overall, headlineIsComfort: comfort != nil,
                                stoolFrequency: g?.stoolFrequency, bristol: g?.bristol, symptoms: symptoms, meals: meals)
        }
    }

    // MARK: A device's own readings

    struct DeviceMetric: Sendable, Equatable, Identifiable {
        enum Kind: String, Sendable { case sleep, restingHeartRate, hrv, steps }
        let kind: Kind
        let days: [String]
        let values: [Double?]
        let previousValues: [Double?]
        var id: String { kind.rawValue }
        var average: Double? { TrendsEngine.mean(values) }
        var previousAverage: Double? { TrendsEngine.previousMean(previousValues) }
        var latest: Double? { values.last(where: { $0 != nil }) ?? nil }
    }

    /// Sleep, resting heart rate, HRV and steps as ONE source sent them — only the metrics it has rows for.
    static func deviceMetrics(rows: [WearableLabeledRow], sourceId: Int, window: TrendWindow, today: String) -> [DeviceMetric] {
        let byDay = Dictionary(WearableAggregation.days(from: rows.filter { $0.dataSourceId == sourceId }).map { ($0.date, $0) },
                               uniquingKeysWith: { _, later in later })
        let now = days(window, today: today)
        let before = previousDays(window, today: today)
        func metric(_ kind: DeviceMetric.Kind, _ pick: (WearableDay) -> Double?) -> DeviceMetric? {
            let values = now.map { byDay[$0].flatMap(pick) }
            let previous = before.map { byDay[$0].flatMap(pick) }
            guard values.contains(where: { $0 != nil }) else { return nil }
            return DeviceMetric(kind: kind, days: now, values: values, previousValues: previous)
        }
        return [
            metric(.sleep) { $0.sleepHours },
            metric(.restingHeartRate) { $0.restingHr.map(Double.init) },
            metric(.hrv) { $0.hrvMs },
            metric(.steps) { $0.steps.map(Double.init) },
        ].compactMap { $0 }
    }

    // MARK: The whole page

    struct Page: Sendable, Equatable {
        let window: TrendWindow
        let today: String
        let days: [String]
        let index: Index
        let seriesBySignal: [TrendSignal: Series]
        let sentences: [TrendSignal: String]
        let score: Score
        let adherence: Adherence
        let supplementNames: [String]
        let devices: [Device]
        let deviceMetrics: [String: [DeviceMetric]]
        let sleep: SleepSummary
        let food: [FoodDay]
        let digestion: [DigestionDay]
        let patterns: [SharedPattern]
        let hasAnyLog: Bool

        func series(_ signal: TrendSignal) -> Series? { seriesBySignal[signal] }
        func sentence(_ signal: TrendSignal) -> String { sentences[signal] ?? "" }
    }

    static func page(_ raw: TrendsRaw, window: TrendWindow, calendar: Calendar) -> Page {
        let index = Index(raw)
        var bySignal: [TrendSignal: Series] = [:]
        var sentences: [TrendSignal: String] = [:]
        for signal in TrendSignal.allCases {
            let s = Self.series(signal, window: window, today: raw.today, index: index)
            bySignal[signal] = s
            sentences[signal] = TrendSentence.sentence(for: signal, goodness: s.values)
        }
        let devices = Self.devices(raw)
        let windowDays = days(window, today: raw.today)
        var metrics: [String: [DeviceMetric]] = [:]
        for device in devices {
            metrics[device.key] = deviceMetrics(rows: raw.wearableRows, sourceId: device.sourceId, window: window, today: raw.today)
        }
        return Page(
            window: window, today: raw.today, days: windowDays, index: index, seriesBySignal: bySignal, sentences: sentences,
            score: scoreSummary(window: window, today: raw.today, index: index),
            adherence: adherence(plan: raw.plan, window: window, today: raw.today),
            supplementNames: raw.supplementNames,
            devices: devices, deviceMetrics: metrics,
            sleep: sleepSummary(raw, window: window),
            food: foodDays(meals: raw.meals, reactions: raw.reactions, days: windowDays, calendar: calendar),
            digestion: digestionDays(raw, window: window, calendar: calendar),
            patterns: raw.patterns.compactMap(SharedPatternText.make),
            hasAnyLog: raw.hasAnyLog
        )
    }
}

// MARK: - Formatting

enum TrendsFormat {
    /// "7.4" — an average, one decimal.
    static func oneDecimal(_ v: Double, locale: Locale = .current) -> String { HealthFormat.decimal(v, digits: 1, locale: locale) }

    /// "7" — a day's value, whole.
    static func whole(_ v: Double) -> String { String(Int(v.rounded())) }

    /// "7 h 02" from minutes.
    static func hours(minutes: Int) -> String { HealthFormat.hours(Double(minutes) / 60) }

    /// "7 h 02" from hours.
    static func hours(_ h: Double) -> String { HealthFormat.hours(h) }

    /// A `YYYY-MM-DD` day as the member reads it: "Sun 9". The day key is a key, not a moment: formatted in UTC.
    static func dayLabel(_ day: String, locale: Locale = .current) -> String {
        format(day, template: "EEEd", locale: locale)
    }

    static func longDayLabel(_ day: String, locale: Locale = .current) -> String {
        format(day, template: "EEEdMMM", locale: locale)
    }

    /// "S" · "M" … the weekday's initial.
    static func weekdayInitial(_ day: String, locale: Locale = .current) -> String {
        format(day, template: "EEEEE", locale: locale)
    }

    static func dayNumber(_ day: String) -> String {
        String(Int(day.suffix(2)) ?? 0)
    }

    private static func format(_ day: String, template: String, locale: Locale) -> String {
        guard let date = HabitEngine.date(day) else { return day }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "avg 6.9 · previous 14 days 6.4" — or just the average when there is no earlier window to compare with.
    static func averageLine(average: String?, previous: String?, days: Int) -> String {
        guard let average else { return String(localized: "trends.noData", defaultValue: "Nothing logged in this period yet") }
        guard let previous else { return String(localized: "trends.avgOnly", defaultValue: "avg \(average)") }
        return String(localized: "trends.avgPrev", defaultValue: "avg \(average) · previous \(days) days \(previous)")
    }

    /// "Today" · "Yesterday" · "Fri 7 Nov".
    static func relativeDay(_ day: String, today: String) -> String {
        if day == today { return String(localized: "day.today", defaultValue: "Today") }
        if day == HabitEngine.shift(today, by: -1) { return String(localized: "day.yesterday", defaultValue: "Yesterday") }
        return longDayLabel(day)
    }

    /// "Single" bands on the check-in's wake count, as "0×" · "1–2×" · "3+×".
    static func wakeLabel(_ band: String?) -> String {
        switch band {
        case "0": "0×"
        case "1_2": "1–2×"
        case "3plus": "3+×"
        default: "–"
        }
    }

    /// "23:05 → 06:50".
    static func bedToWake(bed: String?, wake: String?) -> String {
        guard let bed, let wake else { return "–" }
        return "\(bed) → \(wake)"
    }
}
