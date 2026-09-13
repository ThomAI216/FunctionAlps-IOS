import Foundation

// The SECOND place a baseline can come from (the Expo `intake-baseline.ts` + `baseline-prefill.ts` +
// `prefill-copy.ts`): the intake questionnaire the client completed with the practice, plus the date of
// birth on their clinical record.
//
// Two sources, in a fixed order of trust:
//   1. `nb_patient_app_profiles` — what the MEMBER themselves last saved. Prefilled silently.
//   2. The intake questionnaire + clinical DOB — what the PRACTICE holds. Fills only the gaps left by (1),
//      and every value it supplies is LABELLED on screen ("From your record").
//
// Data minimisation: only sex / height / weight / activity / DOB cross the boundary — `SupabaseBackend`
// selects those four answer keys out of the ~81-key `answers` blob and nothing else reaches a model, a log
// or a screen. Every mapper is wrong in the safe direction: unrecognised, unparseable or out of range ⇒
// nil ⇒ "ask them". A wrong prefill is worse than a question, because the member may well nod it through.

/// The five baseline values, each independently present or absent.
struct PartialBaseline: Sendable, Equatable {
    var sex: MemberProfile.Sex? = nil
    var age: Int? = nil
    var heightCm: Double? = nil
    var weightKg: Double? = nil
    var activity: ActivityLevel? = nil

    static let empty = PartialBaseline()

    /// True when all five are present — the profile alone can then step over the baseline screens.
    var isComplete: Bool { sex != nil && age != nil && heightCm != nil && weightKg != nil && activity != nil }
}

/// The form's fields, in SCREEN order (the sentence names them in this order, never in argument order).
enum BaselineField: String, Sendable, CaseIterable, Hashable {
    case age, sex, heightCm, weightKg, activity
}

/// What the practice holds, as the backend hands it over: the four intake answers as typed, when the
/// questionnaire was submitted, and the clinical date of birth. Nothing else leaves the questionnaire.
struct IntakeBaselineRead: Sendable, Equatable {
    var gender: String? = nil
    var heightCm: String? = nil
    var weightNow: String? = nil
    var activity: String? = nil
    /// ISO timestamp — `submitted_at`, else `updated_at`.
    var capturedOn: String? = nil
    /// `patients.date_of_birth` as `YYYY-MM-DD`.
    var dateOfBirth: String? = nil
}

/// The merged answer: values, where each came from, and what is still missing.
struct BaselinePrefill: Sendable, Equatable {
    enum Origin: Sendable, Equatable { case member, record }
    var values: PartialBaseline
    var origins: [BaselineField: Origin]
    /// When the practice's record was captured — only when something actually came from it.
    var capturedOn: String?
    /// Fields taken from the practice's record — the ones that get a chip.
    var fromRecord: [BaselineField]
    /// Fields with no value from anywhere — the ones still to answer.
    var missing: [BaselineField]

    /// The banner only makes sense when the practice supplied something AND something is still outstanding:
    /// all-known skips the screen, nothing-known keeps the original copy.
    var showsBanner: Bool { !fromRecord.isEmpty && !missing.isEmpty }
}

enum IntakeBaselineLogic {
    // MARK: Field mappers (pure)

    /// `answers.gender` is free text against a picker ("Female"); FR wordings too. Anything the two-branch
    /// energy formula cannot place — including a non-binary answer — is nil: ask, never guess.
    static func sex(fromIntake raw: String?) -> MemberProfile.Sex? {
        guard let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if ["female", "femme", "f", "woman", "femelle"].contains(v) { return .female }
        if ["male", "homme", "m", "man", "mâle"].contains(v) { return .male }
        return nil
    }

    /// The intake's vocabulary → the DB's five keys. `extremely_active` has NO source value and is never
    /// auto-selected: a client who trains twice a day still gets to say so themselves.
    private static let activityFromIntake: [String: ActivityLevel] = [
        "sedentary": .sedentary, "sédentaire": .sedentary,
        "light": .lightlyActive, "légère": .lightlyActive, "legere": .lightlyActive,
        "moderate": .moderatelyActive, "modérée": .moderatelyActive, "moderee": .moderatelyActive,
        "intense": .veryActive,
    ]

    static func activity(fromIntake raw: String?) -> ActivityLevel? {
        guard let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        return activityFromIntake[v]
    }

    /// Parsed, finite, plain digits (a comma decimal accepted), and inside the form's own range.
    private static func number(_ raw: String?, in range: ClosedRange<Double>) -> Double? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber || $0 == "." }), t.filter({ $0 == "." }).count <= 1,
              let n = Double(t), n.isFinite, range.contains(n) else { return nil }
        return n
    }

    static func height(fromIntake raw: String?) -> Double? { number(raw, in: BaselineLogic.heightRange) }
    static func weight(fromIntake raw: String?) -> Double? { number(raw, in: BaselineLogic.weightRange) }

    /// Whole years at `now`, from a `YYYY-MM-DD` date of birth. Nil outside the form's range, so a
    /// placeholder DOB (1900-01-01 and friends) can never prefill an age nobody would notice was wrong.
    static func age(fromDateOfBirth dob: String?, on now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let dob, !dob.isEmpty else { return nil }
        let parts = dob.prefix(10).split(separator: "-").map { Int($0) }
        guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2],
              let born = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let age = calendar.dateComponents([.year], from: calendar.startOfDay(for: born), to: today).year,
              born <= today, BaselineLogic.ageRange.contains(age) else { return nil }
        return age
    }

    /// Maps one intake read onto the baseline fields it carries.
    static func baseline(from read: IntakeBaselineRead?, now: Date = Date(), calendar: Calendar = .current) -> PartialBaseline {
        guard let read else { return .empty }
        return PartialBaseline(
            sex: sex(fromIntake: read.gender),
            age: age(fromDateOfBirth: read.dateOfBirth, on: now, calendar: calendar),
            heightCm: height(fromIntake: read.heightCm),
            weightKg: weight(fromIntake: read.weightNow),
            activity: activity(fromIntake: read.activity)
        )
    }

    // MARK: The member's own row

    /// The baseline fields present on the profile, each validated independently — deliberately NOT
    /// all-or-nothing: a row holding three good values and two nulls yields three values.
    static func partial(fromProfile p: MemberProfile?) -> PartialBaseline {
        guard let p else { return .empty }
        let sex: MemberProfile.Sex? = (p.sex == .male || p.sex == .female) ? p.sex : nil
        let age = p.age.flatMap { BaselineLogic.ageRange.contains($0) ? $0 : nil }
        let height = p.heightCm.flatMap { BaselineLogic.heightRange.contains($0) ? $0 : nil }
        let weight = p.weightKg.flatMap { BaselineLogic.weightRange.contains($0) ? $0 : nil }
        return PartialBaseline(sex: sex, age: age, heightCm: height, weightKg: weight, activity: p.activityLevel.flatMap(ActivityLevel.init(rawValue:)))
    }

    // MARK: Merge

    /// Field by field: the member's own value wins, the practice's record fills the gap, and each surviving
    /// value remembers which it was. "From your record" is a claim about provenance and has to stay true
    /// per field, not be sprayed across the form because one value came from the intake.
    static func merge(profile: PartialBaseline, intake: PartialBaseline, capturedOn: String?) -> BaselinePrefill {
        var values = PartialBaseline.empty
        var origins: [BaselineField: BaselinePrefill.Origin] = [:]
        var fromRecord: [BaselineField] = []
        var missing: [BaselineField] = []

        func pick<T>(_ field: BaselineField, _ mine: T?, _ theirs: T?, _ set: (T) -> Void) {
            if let mine { set(mine); origins[field] = .member }
            else if let theirs { set(theirs); origins[field] = .record; fromRecord.append(field) }
            else { missing.append(field) }
        }
        pick(.age, profile.age, intake.age) { values.age = $0 }
        pick(.sex, profile.sex, intake.sex) { values.sex = $0 }
        pick(.heightCm, profile.heightCm, intake.heightCm) { values.heightCm = $0 }
        pick(.weightKg, profile.weightKg, intake.weightKg) { values.weightKg = $0 }
        pick(.activity, profile.activity, intake.activity) { values.activity = $0 }

        return BaselinePrefill(values: values, origins: origins, capturedOn: fromRecord.isEmpty ? nil : capturedOn, fromRecord: fromRecord, missing: missing)
    }
}

/// The sentence the baseline screen says when it already knows part of the answer, and the words for the
/// two field chips. ONE template, two slots, every clause conditional on what was actually found — the
/// shapes that make templated copy read as broken (one known, one missing, no date) are what the tests pin.
enum PrefillCopy {
    struct Banner: Sendable, Equatable {
        /// Screen title — differs from both "understand" (nothing known) and "confirm" (everything known).
        let title: String
        /// Small caps label on the banner.
        let bannerLabel: String
        let sentence: String
    }

    /// What each field is called INSIDE a sentence ("your weight"), not the form headings.
    static func noun(_ field: BaselineField) -> String {
        switch field {
        case .sex: String(localized: "prefill.noun.sex", defaultValue: "sex")
        case .age: String(localized: "prefill.noun.age", defaultValue: "age")
        case .heightCm: String(localized: "prefill.noun.height", defaultValue: "height")
        case .weightKg: String(localized: "prefill.noun.weight", defaultValue: "weight")
        case .activity: String(localized: "prefill.noun.activity", defaultValue: "activity level")
        }
    }

    /// ["sex"] → "sex" · ["sex","weight"] → "sex and weight" · three → "sex, weight and activity level".
    static func joinNaturally(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        if items.count == 1 { return last }
        let and = String(localized: "prefill.and", defaultValue: " and ")
        return items.dropLast().joined(separator: ", ") + and + last
    }

    /// Sorts fields into screen order and names them.
    static func nameFields(_ fields: [BaselineField]) -> String {
        joinNaturally(BaselineField.allCases.filter { fields.contains($0) }.map(noun))
    }

    /// "12 June" — day and month, adding the year only when it is not the current one.
    static func formatCapturedOn(_ iso: String?, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> String? {
        guard let iso, let date = ISO8601.parse(iso) else { return nil }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }

    /// The banner for a partly-known baseline. Callers only reach here when BOTH lists are non-empty, but it
    /// still degrades gracefully rather than emitting a dangling clause.
    static func banner(known: [BaselineField], missing: [BaselineField], capturedOn: String?, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> Banner {
        let date = formatCapturedOn(capturedOn, now: now, locale: locale, calendar: calendar)
        let source = date.map { String(localized: "prefill.source.date", defaultValue: "the questionnaire you completed on \($0)") }
            ?? String(localized: "prefill.source.record", defaultValue: "your FunctionAlps record")
        let brought = known.isEmpty ? "" : String(localized: "prefill.brought", defaultValue: "We've brought over your \(nameFields(known)) from \(source).")
        // "just those two" only earns its place at exactly two — at one it is wrong, past two it stops reassuring.
        let tail = missing.count == 2 ? String(localized: "prefill.justTwo", defaultValue: " · just those two") : ""
        let still = missing.isEmpty ? "" : String(localized: "prefill.still", defaultValue: "We still need your \(nameFields(missing))\(tail).")
        return Banner(
            title: String(localized: "prefill.title", defaultValue: "Let’s fill in the gaps."),
            bannerLabel: String(localized: "prefill.bannerLabel", defaultValue: "From your FunctionAlps record"),
            sentence: [brought, still].filter { !$0.isEmpty }.joined(separator: " ")
        )
    }

    /// Chip on a field we filled in for them.
    static var chipKnown: String { String(localized: "prefill.chip.known", defaultValue: "From your record") }
    /// Chip on a field still to answer.
    static var chipNeeded: String { String(localized: "prefill.chip.needed", defaultValue: "Needed") }

    /// The line under a prefilled weight. Weight moves, and a figure from months ago nodded through is worse
    /// than one never offered — so the date is shown WITH an explicit invitation to change it.
    static func weightRecordedNote(_ capturedOn: String?, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> String? {
        guard let date = formatCapturedOn(capturedOn, now: now, locale: locale, calendar: calendar) else { return nil }
        return String(localized: "prefill.weightNote", defaultValue: "Recorded \(date) · change it if it’s moved.")
    }
}
