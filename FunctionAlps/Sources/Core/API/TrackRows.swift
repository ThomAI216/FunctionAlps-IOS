import Foundation

// The Foundation Track's wire shapes (CM OS migration `20261006_foundation_track.sql`, the jsonb shapes of
// `supabase/seed/foundation_track_seed.py`). Decoded with `TrackJSON.decoder` — keys VERBATIM — and mapped onto
// the domain types in `Models/FoundationTrack.swift`. A malformed element (an action without a key, an option
// without a value) is dropped, never fails the day or the questionnaire.

/// Explicit snake_case keys: the rows are decoded without a key strategy.
private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where K == Key {
    func string(_ k: String) -> String? {
        guard let s = try? decodeIfPresent(String.self, forKey: Key(k)) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : s
    }
    func int(_ k: String) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: Key(k)) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: Key(k)) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: Key(k)), let d = Double(s) { return Int(d.rounded()) }
        return nil
    }
    func double(_ k: String) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: Key(k)) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: Key(k)) { return Double(s) }
        return nil
    }
    func bool(_ k: String) -> Bool? { try? decodeIfPresent(Bool.self, forKey: Key(k)) }
    func json(_ k: String) -> JSONValue? {
        guard let v = try? decodeIfPresent(JSONValue.self, forKey: Key(k)), v != .null else { return nil }
        return v
    }
}

// MARK: - member_track_status

struct TrackStatusWire: Decodable, Sendable {
    let status: TrackStatus?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let raw = c.string("status"), let state = TrackStatus.State(rawValue: raw) else { status = nil; return }
        var s = TrackStatus(state: state)
        s.day = c.int("day") ?? 0
        s.days = c.int("days") ?? 14
        s.modulesDone = c.int("modules_done") ?? 0
        s.modulesTotal = c.int("modules_total") ?? 0
        s.mealsExpected = c.int("meals_expected") ?? 0
        s.mealsLogged = c.int("meals_logged") ?? 0
        s.mealsPct = c.int("meals_pct")
        s.reviewUnlocked = c.bool("review_unlocked") ?? false
        if case .array(let calls)? = c.json("calls") { s.calls = calls.compactMap(Self.call) }
        s.energyKcalLow = c.int("energy_kcal_low")
        s.energyKcalHigh = c.int("energy_kcal_high")
        s.proteinGLow = c.int("protein_g_low")
        s.proteinGHigh = c.int("protein_g_high")
        status = s
    }

    private static func call(_ value: JSONValue) -> TrackCall? {
        guard case .object(let o) = value, let day = o["day"]?.doubleValue, let minutes = o["minutes"]?.doubleValue else { return nil }
        func flag(_ k: String) -> Bool {
            if case .bool(let b)? = o[k] { return b }
            return o[k]?.scalarText == "true"
        }
        return TrackCall(day: Int(day), minutes: Int(minutes), gated: flag("gated"), open: flag("open"))
    }
}

// MARK: - track_day

struct TrackDayWire: Decodable, Sendable {
    let day: TrackDay

    static let columns = "day,title_en,title_fr,focus_en,focus_fr,video_url_en,video_url_fr,read_slug,questionnaire_id,actions,push"

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let n = c.int("day") else { throw AppError.decoding(detail: "track_day without day") }
        var d = TrackDay(day: n, titleEn: c.string("title_en") ?? "")
        d.titleFr = c.string("title_fr")
        d.focusEn = c.string("focus_en")
        d.focusFr = c.string("focus_fr")
        d.videoUrlEn = c.string("video_url_en")
        d.videoUrlFr = c.string("video_url_fr")
        d.readSlug = c.string("read_slug")
        d.questionnaireId = c.string("questionnaire_id")
        if case .array(let items)? = c.json("actions") { d.actions = items.compactMap(Self.action) }
        if case .object(let push)? = c.json("push") {
            for (moment, value) in push {
                guard let m = TrackMoment(rawValue: moment), let p = Self.push(value) else { continue }
                d.push[m] = p
            }
        }
        day = d
    }

    static func action(_ value: JSONValue) -> TrackAction? {
        guard case .object(let o) = value, let key = o["key"]?.stringValue, !key.isEmpty,
              let moment = o["moment"]?.stringValue.flatMap(TrackMoment.init(rawValue:)) else { return nil }
        var a = TrackAction(key: key, moment: moment)
        a.habitBankId = o["habit_bank_id"]?.stringValue
        a.face = o["face"]?.stringValue ?? "standard"
        a.titleEn = o["title_en"]?.stringValue
        a.titleFr = o["title_fr"]?.stringValue
        if case .bool(let b)? = o["new"] { a.isNew = b }
        return a
    }

    static func push(_ value: JSONValue) -> TrackPush? {
        switch value {
        case .string(let s): return TrackPush(en: s)
        case .object(let o):
            guard let en = o["en"]?.stringValue else { return nil }
            return TrackPush(en: en, fr: o["fr"]?.stringValue, onlyIf: o["only_if"]?.stringValue)
        default: return nil
        }
    }
}

// MARK: - track_questionnaire · track_question

struct TrackQuestionnaireWire: Decodable, Sendable {
    let questionnaire: TrackQuestionnaire

    static let columns = "id,day,version,title_en,title_fr,intro_en,intro_fr,done_en,done_fr,est_minutes,counts_toward_review"

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let id = c.string("id"), let day = c.int("day") else { throw AppError.decoding(detail: "track_questionnaire without id") }
        var q = TrackQuestionnaire(id: id, day: day, titleEn: c.string("title_en") ?? "")
        q.version = c.int("version") ?? 1
        q.titleFr = c.string("title_fr")
        q.introEn = c.string("intro_en")
        q.introFr = c.string("intro_fr")
        q.doneEn = c.string("done_en")
        q.doneFr = c.string("done_fr")
        q.estMinutes = c.int("est_minutes")
        q.countsTowardReview = c.bool("counts_toward_review") ?? true
        questionnaire = q
    }
}

struct TrackQuestionWire: Decodable, Sendable {
    let questionnaireId: String
    let question: TrackQuestion

    static let columns = "id,questionnaire_id,question_key,screen,position,kind,prompt_en,prompt_fr,help_en,help_fr,options,max_select,"
        + "min_value,max_value,step,unit,required,voice,show_if,prefill,variants"

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let id = c.string("id"), let qid = c.string("questionnaire_id"), let key = c.string("question_key"), let screen = c.int("screen") else {
            throw AppError.decoding(detail: "track_question without id/key/screen")
        }
        questionnaireId = qid
        var q = TrackQuestion(id: id, key: key, screen: screen, kind: c.string("kind").flatMap(TrackQuestionKind.init(rawValue:)), promptEn: c.string("prompt_en") ?? "")
        q.position = c.int("position") ?? 1
        q.promptFr = c.string("prompt_fr")
        q.helpEn = c.string("help_en")
        q.helpFr = c.string("help_fr")
        q.options = c.json("options").flatMap(Self.options)
        q.maxSelect = c.int("max_select")
        q.minValue = c.double("min_value")
        q.maxValue = c.double("max_value")
        q.step = c.double("step")
        q.unit = c.string("unit")
        q.required = c.bool("required") ?? false
        q.voice = c.bool("voice") ?? false
        q.showIf = c.json("show_if").flatMap(Self.condition)
        q.prefill = c.json("prefill").flatMap(Self.prefill)
        if case .array(let items)? = c.json("variants") { q.variants = items.compactMap(Self.variant) }
        question = q
    }

    static func options(_ value: JSONValue) -> TrackOptions? {
        switch value {
        case .object(let o):
            return o["source"]?.stringValue == "track_actions" ? .trackActions : nil
        case .array(let items):
            return .list(items.compactMap { item in
                guard case .object(let o) = item, let v = o["value"]?.scalarText else { return nil }
                var option = TrackOption(value: v, labelEn: o["label_en"]?.stringValue ?? v)
                option.labelFr = o["label_fr"]?.stringValue
                if case .bool(let b)? = o["free_text"] { option.freeText = b }
                return option
            })
        default:
            return nil
        }
    }

    static func condition(_ value: JSONValue) -> TrackCondition? {
        guard case .object(let o) = value else { return nil }
        var c = TrackCondition()
        c.key = o["key"]?.stringValue
        c.eq = o["eq"]
        if case .array(let a)? = o["in"] { c.isIn = a }
        if case .array(let a)? = o["not_in"] { c.notIn = a }
        c.gte = o["gte"]?.doubleValue
        c.lte = o["lte"]?.doubleValue
        if case .bool(let b)? = o["health_connected"] { c.healthConnected = b }
        return c
    }

    static func prefill(_ value: JSONValue) -> TrackPrefill? {
        guard case .object(let o) = value else { return nil }
        switch o["from"]?.stringValue {
        case "answer":
            return o["key"]?.stringValue.map { .answer(key: $0) }
        case "profile":
            if case .array(let fields)? = o["fields"] { return .profile(fields: fields.compactMap(\.stringValue)) }
            return o["field"]?.stringValue.map { .profile(fields: [$0]) }
        case "health":
            return o["metric"]?.stringValue.map { .health(metric: $0) }
        default:
            return nil
        }
    }

    static func variant(_ value: JSONValue) -> TrackVariant? {
        guard case .object(let o) = value, let when = o["when"].flatMap(condition), let prompt = o["prompt_en"]?.stringValue else { return nil }
        return TrackVariant(when: when, promptEn: prompt, promptFr: o["prompt_fr"]?.stringValue)
    }
}

// MARK: - track_questionnaire_response · track_activity

struct TrackResponseWire: Decodable, Sendable {
    let response: TrackResponse

    static let columns = "id,questionnaire_id,answers,status,submitted_at,updated_at"

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let id = c.string("id"), let qid = c.string("questionnaire_id") else { throw AppError.decoding(detail: "track response without id") }
        var answers: [String: JSONValue] = [:]
        if case .object(let o)? = c.json("answers") { answers = o }
        response = TrackResponse(
            id: id, questionnaireId: qid, answers: answers, submitted: c.string("status") == "submitted",
            submittedAt: c.string("submitted_at").flatMap(ISO8601.parse), updatedAt: c.string("updated_at").flatMap(ISO8601.parse)
        )
    }
}

struct TrackActivityWire: Decodable, Sendable {
    let item: TrackActivityItem?

    static let columns = "day,kind,item_key"

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let day = c.int("day"), let kind = c.string("kind").flatMap(TrackActivityItem.Kind.init(rawValue:)), let key = c.string("item_key") else {
            item = nil
            return
        }
        item = TrackActivityItem(day: day, kind: kind, itemKey: key)
    }
}
