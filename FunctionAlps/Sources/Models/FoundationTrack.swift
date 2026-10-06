import Foundation

// The Foundation Track — the fixed 14-day start every new member runs in the app (Thomas, 2026-10-06;
// docs/FOUNDATION_TRACK.md). The content is DATA: the days (video, actions, reminders), the questionnaires and
// their questions are rows the practice writes; the app lays them out and records what the member did. Every
// figure (the day, modules done, meals logged vs expected, whether the review call is open, the energy and
// protein ranges) is computed by `member_track_status` on CM OS (rule 9) — the phone only formats it.
//
// The jsonb shapes (options, show_if, prefill, variants, actions, push) are fixed by
// `supabase/seed/foundation_track_seed.py`. They are decoded with their keys VERBATIM (`TrackJSON.decoder`):
// the shared decoder's snake-case conversion would rewrite answer keys such as `success_3_months`.

/// `member_track_status(p_track_code)` — nil (not enrolled) is the backend's `nil`, not a case here.
struct TrackStatus: Sendable, Equatable {
    enum State: String, Sendable { case invited, active }

    var state: State
    /// 1-based Zurich calendar day since the clock started; can exceed `days` (the track is then "done").
    var day: Int = 0
    var days: Int = 14
    var modulesDone: Int = 0
    var modulesTotal: Int = 0
    var mealsExpected: Int = 0
    var mealsLogged: Int = 0
    var mealsPct: Int?
    var reviewUnlocked = false
    var calls: [TrackCall] = []
    var energyKcalLow: Int?
    var energyKcalHigh: Int?
    var proteinGLow: Int?
    var proteinGHigh: Int?
}

/// One in-app call this member is offered; `open` is the server's answer (day reached, and the review rule or
/// Thomas's override for a gated one).
struct TrackCall: Sendable, Equatable, Hashable {
    let day: Int
    let minutes: Int
    let gated: Bool
    let open: Bool
}

/// When an action belongs to the day. `day` = any time ("during the day").
enum TrackMoment: String, Sendable, Equatable, Hashable, CaseIterable {
    case morning, midday, evening, day

    static let order: [TrackMoment] = [.morning, .midday, .evening, .day]
}

/// One action of a track day (`track_day.actions[]`).
struct TrackAction: Sendable, Equatable, Identifiable {
    let key: String
    let moment: TrackMoment
    /// The `habit_bank` card behind it, when there is one (its title, versions and how-to).
    var habitBankId: String?
    /// `easy` · `standard` · `further` — which version of the card's title the day shows.
    var face: String = "standard"
    /// The practice's own title for this action; overrides the card's.
    var titleEn: String?
    var titleFr: String?
    /// First day of this action: the card says "New today".
    var isNew = false

    var id: String { key }
}

/// One reminder text of a day (`track_day.push.<moment>`).
struct TrackPush: Sendable, Equatable {
    let en: String
    var fr: String?
    /// `review_unlocked` = only when the review call is open.
    var onlyIf: String?
}

/// One `track_day` row.
struct TrackDay: Sendable, Equatable, Identifiable {
    let day: Int
    let titleEn: String
    var titleFr: String?
    var focusEn: String?
    var focusFr: String?
    var videoUrlEn: String?
    var videoUrlFr: String?
    var readSlug: String?
    var questionnaireId: String?
    var actions: [TrackAction] = []
    /// Keyed by `morning` · `midday` · `evening`.
    var push: [TrackMoment: TrackPush] = [:]

    var id: Int { day }
}

/// What a question renders.
enum TrackQuestionKind: String, Sendable, Equatable {
    case single, multi, text, number, time, slider, confirm, info
    case connectHealth = "connect_health"
    case enableNotifications = "enable_notifications"
}

/// One choice of a single/multi question.
struct TrackOption: Sendable, Equatable, Identifiable {
    let value: String
    let labelEn: String
    var labelFr: String?
    /// Choosing it reveals a text field, stored as `<question_key>_other`.
    var freeText = false

    var id: String { value }
}

/// `track_question.options`: a fixed list, or built from the actions the member had (`{"source":"track_actions"}`).
enum TrackOptions: Sendable, Equatable {
    case list([TrackOption])
    case trackActions
}

/// `show_if` (and a variant's `when`): every clause present must hold.
struct TrackCondition: Sendable, Equatable {
    var key: String?
    var eq: JSONValue?
    var isIn: [JSONValue]?
    var notIn: [JSONValue]?
    var gte: Double?
    var lte: Double?
    var healthConnected: Bool?
}

/// `prefill`: what was already said — shown, not re-asked.
enum TrackPrefill: Sendable, Equatable {
    /// The latest value of `key` across the member's responses.
    case answer(key: String)
    /// `nb_patient_app_profiles` columns (the baseline line).
    case profile(fields: [String])
    /// From Apple Health on this phone (`bedtime`).
    case health(metric: String)
}

/// A prompt for a member whose answers match `when` (the first match wins).
struct TrackVariant: Sendable, Equatable {
    let when: TrackCondition
    let promptEn: String
    var promptFr: String?
}

/// One `track_question` row.
struct TrackQuestion: Sendable, Equatable, Identifiable {
    let id: String
    let key: String
    let screen: Int
    var position: Int = 1
    /// nil = a kind this build does not know (never shown, never blocks).
    let kind: TrackQuestionKind?
    let promptEn: String
    var promptFr: String?
    var helpEn: String?
    var helpFr: String?
    var options: TrackOptions?
    var maxSelect: Int?
    var minValue: Double?
    var maxValue: Double?
    var step: Double?
    var unit: String?
    var required = false
    var voice = false
    var showIf: TrackCondition?
    var prefill: TrackPrefill?
    var variants: [TrackVariant] = []
}

/// One `track_questionnaire` row with its questions (ordered by screen, then position).
struct TrackQuestionnaire: Sendable, Equatable, Identifiable {
    let id: String
    let day: Int
    var version: Int = 1
    let titleEn: String
    var titleFr: String?
    var introEn: String?
    var introFr: String?
    var doneEn: String?
    var doneFr: String?
    var estMinutes: Int?
    var countsTowardReview = true
    var questions: [TrackQuestion] = []
}

/// The member's answers to one questionnaire (`track_questionnaire_response`, one row per member per module).
struct TrackResponse: Sendable, Equatable, Identifiable {
    let id: String
    let questionnaireId: String
    var answers: [String: JSONValue]
    var submitted: Bool
    var submittedAt: Date?
    var updatedAt: Date?
}

/// What the member did on a day (`track_activity`): an action checked, the video played, the read opened.
struct TrackActivityItem: Sendable, Hashable {
    enum Kind: String, Sendable { case action, video, read }
    let day: Int
    let kind: Kind
    /// The action key, or `day` for the video / read.
    let itemKey: String
}

/// The write for one questionnaire: answers saved as they are, or submitted (frozen) with them.
struct TrackResponseWrite: Sendable, Equatable {
    let patientId: String
    let questionnaireId: String
    var version: Int = 1
    let answers: [String: JSONValue]
    let submit: Bool
    let at: Date
}

/// The day-7 summary as a member may read it: approved by a practitioner (RLS returns no other row).
struct TrackSummary: Sendable, Equatable, Identifiable {
    let id: String
    let day: Int
    var approvedAt: Date?
    let content: TrackSummaryContent
}

/// `track_summary.content` v1 — the fixed format CLINICAL writes (`lib/foundation-track/summary-content.ts`,
/// `SummaryContentV1`): what we learned (five sections, the only part a model drafts, approved by a human before
/// a member can read it), the goals, the actions new in week 2 and the two ranges. The app renders it as written;
/// `provenance` and `ai_derived` are the practice's bookkeeping and are never read.
struct TrackSummaryContent: Sendable, Equatable {
    struct Learned: Sendable, Equatable, Identifiable {
        /// `context` · `food` · `movement` · `sleep` · `stress`.
        let key: String
        let text: String
        var id: String { key }
    }

    struct Goal: Sendable, Equatable, Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    struct WeekTwoAction: Sendable, Equatable, Identifiable {
        let key: String
        let day: Int
        let moment: TrackMoment?
        let title: String
        var id: String { "\(day).\(key)" }
    }

    struct Range: Sendable, Equatable {
        let low: Int
        let high: Int
    }

    /// The sections in the order the practice writes them.
    static let learnedOrder = ["context", "food", "movement", "sleep", "stress"]

    var language: String?
    var learned: [Learned] = []
    /// `day1` or `day6` (the re-pick).
    var goalsSource: String?
    var goals: [Goal] = []
    /// By day, then moment.
    var weekTwoActions: [WeekTwoAction] = []
    var energyKcal: Range?
    var proteinG: Range?

    var isEmpty: Bool { learned.isEmpty && goals.isEmpty && weekTwoActions.isEmpty && energyKcal == nil && proteinG == nil }

    /// Version 1 for a member, or nothing: another version, another audience or another shape is not guessed at —
    /// the app then shows no summary rather than half of one. Inside v1, a missing or malformed part is left out.
    static func decode(_ value: JSONValue?) -> TrackSummaryContent? {
        guard case .object(let o)? = value, o["version"]?.doubleValue == 1 else { return nil }
        if let audience = o["audience"]?.stringValue, audience != "member" { return nil }
        var c = TrackSummaryContent()
        c.language = o["language"]?.stringValue
        if case .object(let learned)? = o["learned"] {
            c.learned = learnedOrder.compactMap { key -> Learned? in
                guard let text = learned[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return Learned(key: key, text: text)
            }
        }
        if case .object(let goals)? = o["goals"] {
            c.goalsSource = goals["source"]?.stringValue
            if case .array(let items)? = goals["items"] {
                c.goals = items.compactMap { item -> Goal? in
                    guard case .object(let g) = item, let label = g["label"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !label.isEmpty else { return nil }
                    return Goal(value: g["value"]?.scalarText ?? label, label: label)
                }
            }
        }
        if case .array(let actions)? = o["week2_actions"] {
            let parsed = actions.compactMap { item -> WeekTwoAction? in
                guard case .object(let a) = item, let key = a["key"]?.stringValue, let day = a["day"]?.doubleValue,
                      let title = a["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
                return WeekTwoAction(key: key, day: Int(day), moment: a["moment"]?.stringValue.flatMap(TrackMoment.init(rawValue:)), title: title)
            }
            func rank(_ m: TrackMoment?) -> Int { m.flatMap { TrackMoment.order.firstIndex(of: $0) } ?? TrackMoment.order.count }
            c.weekTwoActions = parsed.enumerated()
                .sorted { ($0.element.day, rank($0.element.moment), $0.offset) < ($1.element.day, rank($1.element.moment), $1.offset) }
                .map(\.element)
        }
        c.energyKcal = range(o["energy_kcal"])
        c.proteinG = range(o["protein_g"])
        return c
    }

    private static func range(_ value: JSONValue?) -> Range? {
        guard case .object(let r)? = value, let low = r["low"]?.doubleValue, let high = r["high"]?.doubleValue,
              low > 0, high >= low else { return nil }
        return Range(low: Int(low.rounded()), high: Int(high.rounded()))
    }
}

// MARK: - JSON (keys verbatim)

extension JSONValue: Decodable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: any Decoder) throws {
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            var out: [String: JSONValue] = [:]
            for key in object.allKeys { out[key.stringValue] = try object.decode(JSONValue.self, forKey: key) }
            self = .object(out)
            return
        }
        if var array = try? decoder.unkeyedContainer() {
            var out: [JSONValue] = []
            while !array.isAtEnd { out.append(try array.decode(JSONValue.self)) }
            self = .array(out)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let b = try? single.decode(Bool.self) { self = .bool(b) }
        else if let i = try? single.decode(Int.self) { self = .int(i) }
        else if let d = try? single.decode(Double.self) { self = .number(d) }
        else { self = .string(try single.decode(String.self)) }
    }
}

extension JSONValue {
    /// The value as the text a condition or a label lookup compares: strings as they are, numbers without a
    /// trailing `.0`, booleans as `true`/`false`.
    var scalarText: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .number(let d): d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b): b ? "true" : "false"
        case .null, .array, .object: nil
        }
    }

    /// Every scalar of the value (a multi answer's values; a single answer's one).
    var scalarTexts: [String] {
        if case .array(let items) = self { return items.compactMap(\.scalarText) }
        return scalarText.map { [$0] } ?? []
    }

    var doubleValue: Double? {
        switch self {
        case .int(let i): Double(i)
        case .number(let d): d
        case .string(let s): Double(s)
        default: nil
        }
    }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}

/// The decoder for the track's rows: keys verbatim, dates parsed by hand.
enum TrackJSON {
    static var decoder: JSONDecoder { JSONDecoder() }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) } catch { throw AppError.decoding(detail: String(describing: error)) }
    }
}
