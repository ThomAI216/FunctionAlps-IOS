import Foundation

/// The Nutrition pillar's 7-day observation, app side.
///
/// Spec: FunctionAlps-CLINICAL `docs/wiki/four-pillars/08_NUTRITION_PILLAR_SPEC.md`.
/// Brief: `docs/NUTRITION_TRACK_IMPLEMENTATION.md`.
///
/// The derivation, coverage and safety rules live in
/// `clinical-dashboard/lib/nutrition-pillar/`. Nothing here computes a metric and
/// nothing here decides a flag.
///
/// THIS FEATURE DOES NOT BUILD A MEAL LOGGER. `Features/Food/` already has one and
/// it stays. A track annotates it: one small row alongside each meal, one per day.
/// If you are writing a second photo picker or a second analysis poller, stop.
///
/// Two product rules these types exist to keep honest:
///  1. **No score.** Not a nutrition score, not a grade, not a streak. `FAColor.scale`
///     — the 5-level functional ramp — is deliberately never applied here. And note
///     what is absent below: none of these types has a meal-score field. The five on
///     `MealLog` stay in `Features/Food/` and have no route into the track.
///  2. **An unconfirmed inference is not an answer.** A model's guess about what was
///     on a plate is provisional until a human agrees, and the two must never render
///     the same. This is the sleep track's `ThryveMainSleepLatency = 0` in a new hat.

// MARK: - The window

/// Why a member started a week. Same machinery either way — the safety screen in
/// particular is identical — only the framing of the question differs. The member
/// who never books an appointment is the asymptomatic one, so curiosity does not
/// get a lighter screen.
enum NutritionTrackIntent: String, Sendable, CaseIterable, Identifiable {
    /// The member named something: afternoon crashes, bloating, never feeling full.
    case focus
    /// Nothing is obviously wrong; they want to see the pattern.
    case baseline
    var id: String { rawValue }
}

/// How long the observation runs.
///
/// `.standard` is seven days: long enough to catch a weekend as well as workdays,
/// short enough that people finish it. `.short` is the corpus's "minimum viable"
/// and **cannot reach high coverage or produce a priority driver** — offer it only
/// to a member who would otherwise not start, never as an equal choice on a picker.
/// `.extended` is for a named experiment, week-varying symptoms, or travel.
enum NutritionTrackProtocolLength: Int, Sendable {
    case short = 3
    case standard = 7
    case extended = 14

    /// A three-day look is a look, not an equivalent look. Say so where it is offered.
    var canReachHighCoverage: Bool { self != .short }
}

/// Which optional signals the member agreed to log (NUT-Q-101).
///
/// Burden is chosen, never imposed. A member who opts into none still gets a real
/// profile — what they ate and when — just not how it felt. The setup screen must
/// say what each one buys and what skipping it costs, and must never present the
/// empty set as a failure to engage.
struct NutritionSignalOptIns: OptionSet, Sendable {
    let rawValue: Int
    static let hunger = NutritionSignalOptIns(rawValue: 1 << 0)
    static let fullness = NutritionSignalOptIns(rawValue: 1 << 1)
    static let energy = NutritionSignalOptIns(rawValue: 1 << 2)
    static let digestion = NutritionSignalOptIns(rawValue: 1 << 3)
    static let stool = NutritionSignalOptIns(rawValue: 1 << 4)
    static let cravings = NutritionSignalOptIns(rawValue: 1 << 5)
}

// MARK: - The day

/// The member's own statement that the day's log is complete.
///
/// **Three states, not two, and this is the rule the whole pillar rests on.**
///
/// A missed morning of the sleep diary is visibly missing — the row is not there
/// and the night drops out of the denominator where everyone can see it. A missed
/// lunch is invisible: the day still has meals in it, so it reads as a day the
/// member ate less. And every error that follows points the same way — fewer eating
/// occasions, less protein, fewer plants, less alcohol, a shorter eating window.
/// All of them look exactly like findings this assessment exists to produce.
///
/// So per-day COUNTS are derived only from `.complete`. `.notSure` and `.incomplete`
/// both behave as not-closed; they are stored apart because a member who said the
/// log was incomplete and one who did not know are different people to a clinician.
enum DayCompleteness: String, Sendable, CaseIterable, Identifiable {
    case complete
    case incomplete
    case notSure
    var id: String { rawValue }

    /// The only value any per-day rate, the eating window or alcohol exposure uses.
    var countsTowardRates: Bool { self == .complete }

    /// What goes to the server. `nil` is "not sure" — never coerced to `false`.
    var storedValue: Bool? {
        switch self {
        case .complete: return true
        case .incomplete: return false
        case .notSure: return nil
        }
    }
}

/// The obligation/free axis — **the same field the Sleep track uses**, deliberately.
/// Eating differs between a Tuesday and a Saturday as much as sleep does, and this
/// is the most reusable contrast in the programme. Do not redeclare it per pillar.
enum NutritionDayType: String, Sendable, CaseIterable, Identifiable {
    case obligation
    case free
    var id: String { rawValue }
}

/// Non-exclusive qualifiers. A day may carry several, or `nothingUnusual` alone.
/// Context, not excuses: a week with a birthday dinner in it is a normal week.
enum NutritionDayModifier: String, Sendable, CaseIterable, Identifiable {
    case travel
    case illness
    case eatingOut = "eating_out"
    case socialEvent = "social_event"
    case trainingHard = "training_hard"
    case menstrual
    var id: String { rawValue }
}

/// Banded on purpose. A litre figure recalled at 22:00 is not a measurement, and a
/// free-text number would invite a precision the data cannot carry.
enum FluidBand: String, Sendable, CaseIterable, Identifiable {
    case under075 = "under_0_75"
    case b075to125 = "0_75_to_1_25"
    case b125to175 = "1_25_to_1_75"
    case b175to25 = "1_75_to_2_5"
    case over25 = "over_2_5"
    var id: String { rawValue }
}

/// One day's close. D01–D06 of the spec, in field order.
///
/// Every optional is an honest unknown, never a zero. A signal the member did not
/// opt into costs that one metric on that one day — never the day.
struct NutritionDayClose: Sendable, Equatable, Identifiable {
    /// The member's OWN local date, in the zone they were actually in. Never a UTC
    /// date: at 00:30 in Zurich a UTC date is yesterday, and a day-boundary bug in
    /// a food log silently moves meals between days.
    let day: String
    var timezone: String?

    /// D01 — the field §2.6 of the brief exists for.
    var completeness: DayCompleteness?
    /// D02
    var dayType: NutritionDayType?
    /// D03
    var modifiers: Set<NutritionDayModifier> = []
    /// D04 — 0…10, the whole day rather than any one meal.
    var digestiveComfort: Int?
    /// D05
    var fluid: FluidBand?
    /// D06 — free text. Never parsed, never summarised, never sent to a model.
    /// A person reads it, and that is the only route from something a member wrote
    /// to somebody seeing it.
    var note: String?

    var completedAt: Date?

    var id: String { day }

    /// Enough to submit. Only D01 is required — everything else is a bonus, and a
    /// close that demanded six answers would not be a thirty-second close.
    var canSubmit: Bool { completeness != nil }
}

// MARK: - The event

enum EatingEventType: String, Sendable, CaseIterable, Identifiable {
    case meal, snack
    case caloricDrink = "caloric_drink"
    case alcohol
    var id: String { rawValue }
}

/// Member-confirmed, never guessed from the clock. A 15:00 meal is a late lunch for
/// some people and an early dinner for others, and the protein-distribution finding
/// is entirely built on this field being right.
enum MealSlot: String, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
}

enum GISymptomSeverity: String, Sendable, CaseIterable, Identifiable {
    case none, mild, moderate, severe
    var id: String { rawValue }
}

/// The pillar's annotation on one eating occasion — a **sidecar**, not a copy.
///
/// `mealLogId` points at the `nb_meal_logs` row when the member photographed it,
/// and is `nil` for a caloric event nobody photographs: a beer, a coffee with
/// sugar. Those still count for eating structure and timing, which is why the
/// field is optional rather than the type being keyed on it.
///
/// Note what is NOT here: calories, macros, micronutrients, and any of the five
/// meal scores. Those live on `MealLog` and stay there.
struct NutritionTrackEvent: Sendable, Equatable, Identifiable {
    let id: String
    /// The eating DAY this belongs to — not necessarily the calendar date it
    /// happened on. See `dayOffset`.
    let day: String
    /// "HH:mm", as recorded.
    var at: String?
    /// `1` when this happened after midnight but belongs to the previous eating
    /// day — a 00:20 snack on the day that started at 07:30.
    ///
    /// **Set it explicitly from the real timestamp against the assigned local
    /// date. Never infer it from the clock.** A heuristic ("anything before 04:00
    /// belongs to yesterday") guesses wrong for exactly the shift workers the day
    /// classification exists to describe, and makes a 00:20 breakfast
    /// indistinguishable from a 00:20 nightcap.
    var dayOffset: Int = 0

    var eventType: EatingEventType = .meal
    var mealSlot: MealSlot?
    /// The photographed meal this annotates, when there is one.
    var mealLogId: String?
    /// For an event with no photo. Short, member-typed, never parsed for meaning.
    var describedAs: String?

    /// The signal taps. Each present only if the member opted into it.
    ///
    /// `hungerPre` and `cravingBefore` belong on the CAPTURE flow, at the moment
    /// before eating — they cannot be recalled accurately two hours later, and
    /// asking then would fabricate data. See §4 of the brief: `MealReactionSheet`
    /// already exists and partially overlaps these, and the answer is to extend it
    /// rather than ship a second sheet that asks the same member twice.
    var hungerPre: Int?
    var fullnessPost: Int?
    var energyAfter: Int?
    var sleepinessAfter: Int?
    var cravingBefore: Int?
    var giSymptomAfter: GISymptomSeverity?
}

// MARK: - The digestive module

/// Stored as the integer 1…7 because that is what the transit-time literature is
/// indexed on. **Never summed, averaged or turned into a gut score** — the profile
/// renders a distribution across 1–2 / 3–5 / 6–7 with its count, which is the most
/// a week can honestly say.
///
/// v1 ships FunctionAlps text descriptors and **no illustration**: the published
/// charts carry their own licensing, and an original instrument never borrows a
/// licensed one's artwork. `chartVersion` exists so a licensed chart can be
/// recorded later without a schema change.
enum BristolType: Int, Sendable, CaseIterable, Identifiable {
    case separateHardLumps = 1
    case lumpySausage = 2
    case crackedSausage = 3
    case smoothSausage = 4
    case softBlobs = 5
    case mushyRagged = 6
    case entirelyLiquid = 7
    var id: Int { rawValue }
}

enum DigestiveSymptomType: String, Sendable, CaseIterable, Identifiable {
    case bloating
    case abdominalPain = "abdominal_pain"
    case reflux, nausea, belching, gas, urgency, diarrhoea
    case constipationSensation = "constipation_sensation"
    case earlyFullness = "early_fullness"
    var id: String { rawValue }
}

enum MealRelation: String, Sendable, CaseIterable, Identifiable {
    case before
    case within1h = "within_1h"
    case oneToThreeH = "one_to_three_h"
    case over3h = "over_3h"
    case unknown
    var id: String { rawValue }
}

/// A stool or a symptom. One type with a discriminator, because both are
/// "something that happened at a time, with a severity, related to a meal".
struct DigestiveEvent: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case stool, symptom }

    let id: String
    let day: String
    var at: String?
    var kind: Kind

    // Stool
    var bristol: BristolType?
    var chartVersion: String?
    var urgency: Int?
    var straining: Int?
    var incompleteEvacuation: Bool?
    var painScore: Int?
    /// Raises an urgent flag server-side. This app never decides that — it records.
    var visibleBlood: Bool?
    var mucus: Bool?

    // Symptom
    var symptomType: DigestiveSymptomType?
    var severity: Int?
    var durationMin: Int?
    var mealRelation: MealRelation?
    var wokeFromSleep: Bool?

    var note: String?
}

// MARK: - Coverage, as the member is told it

/// How much of the week we actually have.
///
/// Two gates, and **this app can move both**: days the member confirmed complete
/// (the day-close screen), and meals whose contents a human checked (the one-tap
/// confirmation). A member who photographs everything, confirms nothing and closes
/// no day gets `.moderate` for ever — not a failure state, a narrower report.
enum NutritionCoverage: String, Sendable {
    case high, moderate, low

    /// Fixed copy. Do not improvise around it: never a percentage presented as a
    /// mark, never a red state, never "you failed".
    var memberCopy: String {
        switch self {
        case .low:
            return String(
                localized: "nutrition.coverage.low",
                defaultValue: "We need a little more observation before drawing a conclusion."
            )
        case .moderate:
            return String(
                localized: "nutrition.coverage.moderate",
                defaultValue: "Enough to describe your week and name something worth testing."
            )
        case .high:
            return String(
                localized: "nutrition.coverage.high",
                defaultValue: "A full week, with what was in almost every meal confirmed."
            )
        }
    }
}

/// The running window, as the app holds it.
struct NutritionTrack: Sendable, Equatable, Identifiable {
    let id: String
    let intent: NutritionTrackIntent
    let length: NutritionTrackProtocolLength
    let startedOn: String
    var plannedEndOn: String?
    /// NUT-Q-104 — the member's own question, and the thing the results page
    /// answers first. Stored on the assessment, not buried in an answers blob.
    var primaryQuestion: String?
    var optIns: NutritionSignalOptIns
    var digestiveModuleOn: Bool

    var days: [NutritionDayClose] = []

    /// Days the member confirmed complete. The denominator of every per-day rate,
    /// and the number the track screen should show — not "days logged", which
    /// flatters.
    var confirmedDayCount: Int {
        days.filter { $0.completeness?.countsTowardRates == true }.count
    }

    /// Displayed as-is beside the count. A tier without its denominator is a grade.
    var dayTarget: Int { length.rawValue }
}
