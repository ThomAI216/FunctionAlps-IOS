import Foundation

/// The functional check-in's questions, ported from the Expo app's `lib/checkin/functional-schema.ts`
/// and `pill-catalog.ts`. Labels resolve through the string catalog (EN/FR).
struct SliderSpec: Sendable, Identifiable {
    let key: String
    let label: String
    let lowLabel: String
    let highLabel: String
    /// Five words, ordered by value (low → high).
    let words: [String]
    var id: String { key }
}

struct PillOption: Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

/// A precision pill group rendered directly under the section (`after`) that triggered it.
struct PillModule: Sendable, Identifiable {
    let key: String
    let title: String?
    let after: String
    /// One active pill at a time (scale-like lists).
    let single: Bool
    let when: @Sendable (DimAnswers) -> Bool
    let options: [PillOption]
    var id: String { key }
}

struct DimensionSpec: Sendable, Identifiable {
    let key: DimKey
    let title: String
    let accentHex: UInt32
    let sliders: [SliderSpec]
    let hasSleepInputs: Bool
    let pills: [PillModule]
    var id: DimKey { key }
}

enum BandLevel: Sendable, Equatable { case low, mid, high }

enum FunctionalSchema {
    /// `<40` low, `40–60` mid, `>60` high — `bandLevel` in score-bands.ts.
    static func bandLevel(_ v: Double?) -> BandLevel? {
        guard let v else { return nil }
        let c = min(100, max(0, v))
        if c < 40 { return .low }
        if c <= 60 { return .mid }
        return .high
    }

    private static func lvl(_ a: DimAnswers, _ key: String) -> BandLevel? { bandLevel(a.sliders[key]) }
    private static func has(_ a: DimAnswers, _ key: String) -> Bool { a.sliders[key] != nil }
    private static func opt(_ key: String, _ label: String) -> PillOption { PillOption(key: key, label: label) }
    private static func module(_ key: String, _ title: String?, after: String, single: Bool = false, when: @escaping @Sendable (DimAnswers) -> Bool, _ options: [PillOption]) -> PillModule {
        PillModule(key: key, title: title, after: after, single: single, when: when, options: options)
    }

    static let timesOfDay: [PillOption] = [
        opt("early_morning", String(localized: "pill.early_morning", defaultValue: "Early morning")),
        opt("morning", String(localized: "pill.morning", defaultValue: "Morning")),
        opt("midday", String(localized: "pill.midday", defaultValue: "Midday")),
        opt("afternoon", String(localized: "pill.afternoon", defaultValue: "Afternoon")),
        opt("evening", String(localized: "pill.evening", defaultValue: "Evening")),
        opt("night", String(localized: "pill.night", defaultValue: "Night")),
    ]

    static let energy = DimensionSpec(
        key: .energy,
        title: String(localized: "dim.energy", defaultValue: "Energy"),
        accentHex: 0xD97706,
        sliders: [
            SliderSpec(key: "body", label: String(localized: "slider.body", defaultValue: "Body"), lowLabel: String(localized: "slider.body.low", defaultValue: "Drained"), highLabel: String(localized: "slider.body.high", defaultValue: "Buzzing"),
                       words: [String(localized: "w.drained", defaultValue: "Drained"), String(localized: "w.low", defaultValue: "Low"), String(localized: "w.steady", defaultValue: "Steady"), String(localized: "w.good", defaultValue: "Good"), String(localized: "w.buzzing", defaultValue: "Buzzing")]),
            SliderSpec(key: "mind", label: String(localized: "slider.mind", defaultValue: "Mind"), lowLabel: String(localized: "slider.mind.low", defaultValue: "Foggy"), highLabel: String(localized: "slider.mind.high", defaultValue: "Sharp"),
                       words: [String(localized: "w.foggy", defaultValue: "Foggy"), String(localized: "w.hazy", defaultValue: "Hazy"), String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.clear", defaultValue: "Clear"), String(localized: "w.sharp", defaultValue: "Sharp")]),
            SliderSpec(key: "stability", label: String(localized: "slider.stability", defaultValue: "Stability"), lowLabel: String(localized: "slider.stability.low", defaultValue: "Swingy"), highLabel: String(localized: "slider.stability.high", defaultValue: "Steady"),
                       words: [String(localized: "w.swingy", defaultValue: "Swingy"), String(localized: "w.uneven", defaultValue: "Uneven"), String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.stable", defaultValue: "Stable"), String(localized: "w.steady", defaultValue: "Steady")]),
        ],
        hasSleepInputs: false,
        pills: [
            module("drained", String(localized: "pills.drained", defaultValue: "What drained you?"), after: "mind",
                   when: { a in has(a, "body") && has(a, "mind") && (lvl(a, "body") == .low || lvl(a, "mind") == .low) },
                   [opt("poor_sleep", String(localized: "pill.poor_sleep", defaultValue: "Poor sleep")), opt("skipped_meals", String(localized: "pill.skipped_meals", defaultValue: "Skipped/late meals")), opt("high_carb", String(localized: "pill.high_carb", defaultValue: "High-carb lunch")), opt("dehydration", String(localized: "pill.dehydration", defaultValue: "Dehydration")), opt("overtraining", String(localized: "pill.overtraining", defaultValue: "Overtraining")), opt("stress", String(localized: "pill.stress", defaultValue: "Stress")), opt("illness", String(localized: "pill.illness", defaultValue: "Illness coming on")), opt("screen_fatigue", String(localized: "pill.screen_fatigue", defaultValue: "Screen fatigue")), opt("needed_caffeine", String(localized: "pill.needed_caffeine", defaultValue: "Needed caffeine")), opt("post_meal_crash", String(localized: "pill.post_meal_crash", defaultValue: "Post-meal crash"))]),
            module("fuelled", String(localized: "pills.fuelled", defaultValue: "What fuelled you?"), after: "mind",
                   when: { a in has(a, "body") && has(a, "mind") && (lvl(a, "body") == .high || lvl(a, "mind") == .high) },
                   [opt("good_sleep", String(localized: "pill.good_sleep", defaultValue: "Good sleep")), opt("protein_breakfast", String(localized: "pill.protein_breakfast", defaultValue: "Protein breakfast")), opt("movement", String(localized: "pill.movement", defaultValue: "Movement")), opt("sunlight", String(localized: "pill.sunlight", defaultValue: "Sunlight")), opt("hydration", String(localized: "pill.hydration", defaultValue: "Hydration")), opt("rest_day", String(localized: "pill.rest_day", defaultValue: "Rest day"))]),
            module("best_moment", String(localized: "pills.best_moment", defaultValue: "Best moment"), after: "stability",
                   when: { a in lvl(a, "stability") != nil && lvl(a, "stability") != .high }, timesOfDay),
            module("worst_dip", String(localized: "pills.worst_dip", defaultValue: "Worst dip"), after: "stability",
                   when: { a in lvl(a, "stability") != nil && lvl(a, "stability") != .high }, timesOfDay),
        ]
    )

    static let sleep = DimensionSpec(
        key: .sleep,
        title: String(localized: "dim.sleep", defaultValue: "Sleep"),
        accentHex: 0x6366F1,
        sliders: [
            SliderSpec(key: "refreshed", label: String(localized: "slider.refreshed", defaultValue: "Refreshed"), lowLabel: String(localized: "slider.refreshed.low", defaultValue: "Wrecked"), highLabel: String(localized: "slider.refreshed.high", defaultValue: "Restored"),
                       words: [String(localized: "w.wrecked", defaultValue: "Wrecked"), String(localized: "w.groggy", defaultValue: "Groggy"), String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.rested", defaultValue: "Rested"), String(localized: "w.restored", defaultValue: "Restored")]),
        ],
        hasSleepInputs: true,
        pills: [
            module("kept_up", String(localized: "pills.kept_up", defaultValue: "What kept you up?"), after: "latency",
                   when: { a in a.specials.latency == "30_60" || a.specials.latency == "gt_60" },
                   [opt("mind_racing", String(localized: "pill.mind_racing", defaultValue: "Mind racing")), opt("stress", String(localized: "pill.stress", defaultValue: "Stress")), opt("heat", String(localized: "pill.heat", defaultValue: "Heat")), opt("cold", String(localized: "pill.cold", defaultValue: "Cold")), opt("pain", String(localized: "pill.pain_discomfort", defaultValue: "Discomfort/pain")), opt("digestion", String(localized: "pill.digestion_reflux", defaultValue: "Digestion/reflux")), opt("noise", String(localized: "pill.noise", defaultValue: "Noise")), opt("light", String(localized: "pill.light", defaultValue: "Light")), opt("caffeine", String(localized: "pill.late_caffeine", defaultValue: "Late caffeine")), opt("screen", String(localized: "pill.late_screen", defaultValue: "Late screen")), opt("alcohol", String(localized: "pill.alcohol", defaultValue: "Alcohol")), opt("late_meal", String(localized: "pill.late_meal", defaultValue: "Late meal"))]),
            module("wind_down", String(localized: "pills.wind_down", defaultValue: "Wind-down?"), after: "latency",
                   when: { a in a.specials.latency == "lt_15" },
                   [opt("consistent", String(localized: "pill.consistent", defaultValue: "Consistent bedtime")), opt("meditation", String(localized: "pill.meditation", defaultValue: "Meditation/breathwork")), opt("reading", String(localized: "pill.reading", defaultValue: "Reading")), opt("no_screens", String(localized: "pill.no_screens", defaultValue: "No screens")), opt("warm_shower", String(localized: "pill.warm_shower", defaultValue: "Warm shower")), opt("magnesium", String(localized: "pill.magnesium", defaultValue: "Magnesium")), opt("dark_cool", String(localized: "pill.dark_cool", defaultValue: "Dark/cool room")), opt("exhausted", String(localized: "pill.exhausted", defaultValue: "Exhausted"))]),
            module("woke_why", String(localized: "pills.woke_why", defaultValue: "Why did you wake?"), after: "wakeCount",
                   when: { a in a.specials.wakeCount == "1_2" || a.specials.wakeCount == "3plus" },
                   [opt("bathroom", String(localized: "pill.bathroom", defaultValue: "Bathroom")), opt("thirst", String(localized: "pill.thirst", defaultValue: "Thirst")), opt("nightmare", String(localized: "pill.nightmare", defaultValue: "Nightmare/dream")), opt("noise", String(localized: "pill.noise", defaultValue: "Noise")), opt("pain", String(localized: "pill.pain", defaultValue: "Pain")), opt("temp", String(localized: "pill.hot_cold", defaultValue: "Hot/cold")), opt("partner_kids", String(localized: "pill.partner_kids", defaultValue: "Partner/kids")), opt("no_reason", String(localized: "pill.no_reason", defaultValue: "No reason"))]),
            module("wake_recovery", String(localized: "pills.wake_recovery", defaultValue: "How long to feel human?"), after: "refreshed", single: true,
                   when: { a in lvl(a, "refreshed") == .low },
                   [opt("fine", String(localized: "pill.woke_fine", defaultValue: "Woke fine")), opt("lt_30", String(localized: "pill.lt_30", defaultValue: "<30 min")), opt("1_2h", String(localized: "pill.1_2h", defaultValue: "1–2h")), opt("half_day", String(localized: "pill.half_day", defaultValue: "Half the day")), opt("still_not", String(localized: "pill.still_not", defaultValue: "Still not"))]),
            module("wake_helped", String(localized: "pills.wake_helped", defaultValue: "What helped you wake?"), after: "refreshed",
                   when: { a in lvl(a, "refreshed") == .low },
                   [opt("coffee", String(localized: "pill.coffee", defaultValue: "Coffee")), opt("movement", String(localized: "pill.movement", defaultValue: "Movement")), opt("shower", String(localized: "pill.shower", defaultValue: "Shower")), opt("sunlight", String(localized: "pill.sunlight", defaultValue: "Sunlight")), opt("breakfast", String(localized: "pill.breakfast", defaultValue: "Breakfast")), opt("breathwork", String(localized: "pill.breathwork", defaultValue: "Breathwork"))]),
        ]
    )

    static let moodPositive: [PillOption] = [
        opt("content", String(localized: "pill.content", defaultValue: "Calm/content")), opt("motivated", String(localized: "pill.motivated", defaultValue: "Motivated")), opt("excited", String(localized: "pill.excited", defaultValue: "Excited")), opt("joyful", String(localized: "pill.joyful", defaultValue: "Joyful")), opt("focused", String(localized: "pill.focused", defaultValue: "Focused")), opt("social", String(localized: "pill.social", defaultValue: "Social")),
    ]
    static let moodNegative: [PillOption] = [
        opt("flat", String(localized: "pill.flat", defaultValue: "Flat/down")), opt("anxious", String(localized: "pill.anxious", defaultValue: "Anxious")), opt("irritable", String(localized: "pill.irritable", defaultValue: "Irritable")), opt("overwhelmed", String(localized: "pill.overwhelmed", defaultValue: "Overwhelmed")), opt("sad", String(localized: "pill.sad", defaultValue: "Sad")), opt("foggy", String(localized: "pill.foggy", defaultValue: "Foggy")),
    ]

    static let mood = DimensionSpec(
        key: .mood,
        title: String(localized: "dim.mood", defaultValue: "Mood"),
        accentHex: 0xDB2777,
        sliders: [
            SliderSpec(key: "mood", label: String(localized: "slider.mood", defaultValue: "Mood"), lowLabel: String(localized: "slider.mood.low", defaultValue: "Low"), highLabel: String(localized: "slider.mood.high", defaultValue: "Bright"),
                       words: [String(localized: "w.low", defaultValue: "Low"), String(localized: "w.down", defaultValue: "Down"), String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.good", defaultValue: "Good"), String(localized: "w.bright", defaultValue: "Bright")]),
        ],
        hasSleepInputs: false,
        pills: [
            module("flavour_pos", String(localized: "pills.flavour", defaultValue: "How did it show up?"), after: "mood", when: { a in lvl(a, "mood") == .high }, moodPositive),
            module("flavour_neg", String(localized: "pills.flavour", defaultValue: "How did it show up?"), after: "mood", when: { a in lvl(a, "mood") == .low }, moodNegative),
            module("flavour_mix", String(localized: "pills.flavour", defaultValue: "How did it show up?"), after: "mood", when: { a in lvl(a, "mood") == .mid }, moodPositive + moodNegative),
            module("drivers", String(localized: "pills.drivers", defaultValue: "What shaped it?"), after: "mood", when: { a in lvl(a, "mood") != nil },
                   [opt("sleep", String(localized: "pill.sleep", defaultValue: "Sleep")), opt("food", String(localized: "pill.food", defaultValue: "Food")), opt("work", String(localized: "pill.work", defaultValue: "Work")), opt("people", String(localized: "pill.people", defaultValue: "People")), opt("movement", String(localized: "pill.movement", defaultValue: "Movement")), opt("weather", String(localized: "pill.weather", defaultValue: "Weather/light")), opt("hormones", String(localized: "pill.hormones", defaultValue: "Hormones"))]),
        ]
    )

    static let helped: [PillOption] = [
        opt("walk", String(localized: "pill.walk", defaultValue: "Walk/nature")), opt("breathwork", String(localized: "pill.breathwork_meditation", defaultValue: "Breathwork/meditation")), opt("exercise", String(localized: "pill.exercise", defaultValue: "Exercise")), opt("social", String(localized: "pill.social", defaultValue: "Social")), opt("rest", String(localized: "pill.rest", defaultValue: "Rest/downtime")), opt("boundaries", String(localized: "pill.boundaries", defaultValue: "Boundaries")), opt("sleep", String(localized: "pill.good_sleep", defaultValue: "Good sleep")),
    ]

    /// Stored as calmness: high = calm/good.
    static let stress = DimensionSpec(
        key: .stress,
        title: String(localized: "dim.stress", defaultValue: "Stress"),
        accentHex: 0xE11D48,
        sliders: [
            SliderSpec(key: "calm", label: String(localized: "slider.calm", defaultValue: "Calmness"), lowLabel: String(localized: "slider.calm.low", defaultValue: "Tense"), highLabel: String(localized: "slider.calm.high", defaultValue: "Calm"),
                       words: [String(localized: "w.tense", defaultValue: "Tense"), String(localized: "w.edgy", defaultValue: "Edgy"), String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.eased", defaultValue: "Eased"), String(localized: "w.calm", defaultValue: "Calm")]),
        ],
        hasSleepInputs: false,
        pills: [
            module("source", String(localized: "pills.source", defaultValue: "What stirred it up?"), after: "calm", when: { a in lvl(a, "calm") == .low || lvl(a, "calm") == .mid },
                   [opt("work", String(localized: "pill.work_deadlines", defaultValue: "Work/deadlines")), opt("money", String(localized: "pill.money", defaultValue: "Money")), opt("relationships", String(localized: "pill.relationships", defaultValue: "Relationships")), opt("health", String(localized: "pill.health", defaultValue: "Health")), opt("news", String(localized: "pill.news", defaultValue: "News")), opt("overcommitted", String(localized: "pill.overcommitted", defaultValue: "Overcommitted")), opt("no_downtime", String(localized: "pill.no_downtime", defaultValue: "No downtime")), opt("poor_sleep", String(localized: "pill.poor_sleep", defaultValue: "Poor sleep"))]),
            module("body_signs", String(localized: "pills.body_signs", defaultValue: "Body signs"), after: "calm", when: { a in lvl(a, "calm") == .low },
                   [opt("shoulders_jaw", String(localized: "pill.shoulders_jaw", defaultValue: "Tight shoulders/jaw")), opt("racing_heart", String(localized: "pill.racing_heart", defaultValue: "Racing heart")), opt("headache", String(localized: "pill.headache", defaultValue: "Headache")), opt("gut", String(localized: "pill.gut_tension", defaultValue: "Gut tension")), opt("breath", String(localized: "pill.shallow_breath", defaultValue: "Shallow breath"))]),
            module("helped", String(localized: "pills.helped", defaultValue: "What helped?"), after: "calm", when: { a in lvl(a, "calm") == .high || lvl(a, "calm") == .mid }, helped),
        ]
    )

    /// Sleep leads: the night is the freshest memory in a morning check-in.
    static let dimensions: [DimensionSpec] = [sleep, energy, mood, stress]

    static func spec(_ key: DimKey) -> DimensionSpec {
        switch key {
        case .energy: energy
        case .sleep: sleep
        case .mood: mood
        case .stress: stress
        }
    }

    static let latencyOptions: [PillOption] = [
        opt("lt_15", "<15m"), opt("15_30", "15–30m"), opt("30_60", "30–60m"), opt("gt_60", ">60m"),
    ]
    static let wakeCountOptions: [PillOption] = [opt("0", "0"), opt("1_2", "1–2"), opt("3plus", "3+")]
}

// MARK: - The context pill catalog (moment screen)

enum PillGroup: String, Sendable, CaseIterable { case dayIntent = "day_intent", fuelled, drained }

enum Pillar: String, Sendable, CaseIterable {
    case nutrition, exercise, mind, emotion, recovery, sleep

    /// One mid-tone hue per pillar (pillar-colors.ts) so a wall of pills reads as a palette.
    var hueHex: UInt32 {
        switch self {
        case .nutrition: 0x4A8A5C
        case .exercise: 0x3F7D68
        case .mind: 0x7A6BA8
        case .emotion: 0xC97B7B
        case .recovery: 0xD4A84E
        case .sleep: 0x5B7FB8
        }
    }
}

struct CatalogPill: Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let group: PillGroup
    let pillar: Pillar
    /// Moments this pill is offered in; nil = every moment.
    let slots: [MomentSlot]?
    var id: String { key }
}

/// Stored-not-scored context: how the member walked into the day, what fuelled or drained them.
enum PillCatalog {
    private static func pill(_ key: String, _ label: String, _ group: PillGroup, _ pillar: Pillar, morningOnly: Bool = false) -> CatalogPill {
        CatalogPill(key: key, label: label, group: group, pillar: pillar, slots: morningOnly ? [.morning] : nil)
    }

    static let all: [CatalogPill] = [
        pill("intent_motivated", String(localized: "cat.intent_motivated", defaultValue: "Motivated"), .dayIntent, .mind, morningOnly: true),
        pill("intent_calm", String(localized: "cat.intent_calm", defaultValue: "Calm"), .dayIntent, .emotion, morningOnly: true),
        pill("intent_hopeful", String(localized: "cat.intent_hopeful", defaultValue: "Hopeful"), .dayIntent, .emotion, morningOnly: true),
        pill("intent_determined", String(localized: "cat.intent_determined", defaultValue: "Determined"), .dayIntent, .mind, morningOnly: true),
        pill("intent_ecstatic", String(localized: "cat.intent_ecstatic", defaultValue: "Over the moon"), .dayIntent, .emotion, morningOnly: true),
        pill("intent_rushed", String(localized: "cat.intent_rushed", defaultValue: "Already rushing"), .dayIntent, .mind, morningOnly: true),
        pill("intent_tense", String(localized: "cat.intent_tense", defaultValue: "Tense"), .dayIntent, .emotion, morningOnly: true),
        pill("intent_heavy", String(localized: "cat.intent_heavy", defaultValue: "Carrying something heavy"), .dayIntent, .emotion, morningOnly: true),
        pill("intent_foggy", String(localized: "cat.intent_foggy", defaultValue: "Foggy"), .dayIntent, .mind, morningOnly: true),
        pill("intent_low", String(localized: "cat.intent_low", defaultValue: "Low"), .dayIntent, .emotion, morningOnly: true),

        pill("good_sleep", String(localized: "cat.good_sleep", defaultValue: "A good night"), .fuelled, .sleep, morningOnly: true),
        pill("protein_breakfast", String(localized: "cat.protein_breakfast", defaultValue: "Protein at breakfast"), .fuelled, .nutrition, morningOnly: true),
        pill("proper_meal", String(localized: "cat.proper_meal", defaultValue: "A proper meal"), .fuelled, .nutrition),
        pill("hydration", String(localized: "cat.hydration", defaultValue: "Plenty of water"), .fuelled, .nutrition),
        pill("workout", String(localized: "cat.workout", defaultValue: "Worked out or went for a run"), .fuelled, .exercise),
        pill("walk_outside", String(localized: "cat.walk_outside", defaultValue: "A walk outside"), .fuelled, .exercise),
        pill("daylight", String(localized: "cat.daylight", defaultValue: "Daylight on my face"), .fuelled, .recovery),
        pill("real_break", String(localized: "cat.real_break", defaultValue: "A real break"), .fuelled, .recovery),
        pill("good_news", String(localized: "cat.good_news", defaultValue: "Good news"), .fuelled, .emotion),
        pill("time_with_friends", String(localized: "cat.time_with_friends", defaultValue: "Time with friends"), .fuelled, .emotion),
        pill("time_with_family", String(localized: "cat.time_with_family", defaultValue: "Time with family"), .fuelled, .emotion),
        pill("laughed_a_lot", String(localized: "cat.laughed_a_lot", defaultValue: "Laughed a lot"), .fuelled, .emotion),
        pill("quiet_time", String(localized: "cat.quiet_time", defaultValue: "Quiet time to myself"), .fuelled, .mind),
        pill("deep_work", String(localized: "cat.deep_work", defaultValue: "Deep focused work"), .fuelled, .mind),
        pill("time_in_nature", String(localized: "cat.time_in_nature", defaultValue: "Time in nature"), .fuelled, .recovery),
        pill("music", String(localized: "cat.music", defaultValue: "Music"), .fuelled, .mind),

        pill("short_night", String(localized: "cat.short_night", defaultValue: "A short night"), .drained, .sleep),
        pill("skipped_meal", String(localized: "cat.skipped_meal", defaultValue: "Skipped a meal"), .drained, .nutrition),
        pill("sugar_dip", String(localized: "cat.sugar_dip", defaultValue: "A sugar dip"), .drained, .nutrition),
        pill("too_much_coffee", String(localized: "cat.too_much_coffee", defaultValue: "Too much coffee"), .drained, .nutrition),
        pill("alcohol", String(localized: "cat.alcohol", defaultValue: "Alcohol"), .drained, .nutrition),
        pill("sat_all_day", String(localized: "cat.sat_all_day", defaultValue: "Sat all day"), .drained, .exercise),
        pill("overworked", String(localized: "cat.overworked", defaultValue: "Overworked"), .drained, .mind),
        pill("screens_too_late", String(localized: "cat.screens_too_late", defaultValue: "Screens too late"), .drained, .sleep),
        pill("hard_conversation", String(localized: "cat.hard_conversation", defaultValue: "A hard conversation"), .drained, .emotion),
        pill("bad_news", String(localized: "cat.bad_news", defaultValue: "Bad news"), .drained, .emotion),
        pill("noise_and_crowds", String(localized: "cat.noise_and_crowds", defaultValue: "Noise and crowds"), .drained, .recovery),
        pill("pain_or_niggles", String(localized: "cat.pain_or_niggles", defaultValue: "Pain or niggles"), .drained, .recovery),
        pill("travel", String(localized: "cat.travel", defaultValue: "Travel"), .drained, .recovery),
        pill("no_time_to_myself", String(localized: "cat.no_time_to_myself", defaultValue: "No time to myself"), .drained, .mind),
    ]

    static func pills(for group: PillGroup, slot: MomentSlot) -> [CatalogPill] {
        all.filter { $0.group == group && ($0.slots?.contains(slot) ?? true) }
    }

    static func pill(_ key: String) -> CatalogPill? { all.first { $0.key == key } }

    /// Groups owned by the catalog on the moment screen (the ENERGY spec's same-named
    /// follow-ups are dropped there so nobody is asked the same question twice).
    static let ownedGroups: Set<String> = Set(PillGroup.allCases.map(\.rawValue))
}
