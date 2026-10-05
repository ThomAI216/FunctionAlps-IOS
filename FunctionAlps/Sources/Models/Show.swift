import Foundation

// "The FunctionAlps Show" — the daily health show inside the members' Library, as the CLINICAL library API serves
// it (`GET {FA_CLINICAL_API_URL}/api/webinars/library` and `/api/webinars/library/<slug>`). The SAME shapes and the
// SAME tolerance as the members web (`src/lib/show/{types,parse}.ts`, branch claude/library-show): the response
// crosses a repo boundary, so nothing is trusted — a malformed item is dropped on its own, an unusable response
// reads as "no show data" (nil) and the Library renders its other sections regardless.
//
// Both API shapes decode. The production API may still answer the OLD shape for a while: no `kind` (→ episode),
// no `upcoming` (→ []), no `series.schedule/time/timezone` (→ the default week at 12:30 Europe/Zurich).

enum ShowTrack: String, Sendable, CaseIterable {
    case movement, nutrition, sleep, mental, intelligence, cross
}

enum ShowKind: String, Sendable {
    case episode, live
}

/// `{ en, fr }` text; either side may be missing.
struct ShowText: Sendable, Equatable, Decodable {
    var en: String?
    var fr: String?

    init(en: String?, fr: String? = nil) {
        self.en = en
        self.fr = fr
    }

    private enum Keys: String, CodingKey { case en, fr }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        en = c.showString(.en)
        fr = c.showString(.fr)
    }

    /// The member's language when the API has it, the other one otherwise ("" when neither).
    func pick(_ lang: String) -> String {
        let e = en?.trimmingCharacters(in: .whitespacesAndNewlines).showNonEmpty
        let f = fr?.trimmingCharacters(in: .whitespacesAndNewlines).showNonEmpty
        return (lang == "fr" ? f ?? e : e ?? f) ?? ""
    }
}

/// One day of the weekly rhythm (ISO weekday, 1 = Monday) at the series' time.
struct ShowSlot: Sendable, Equatable, Decodable {
    let weekday: Int
    let kind: ShowKind
    let track: ShowTrack
    let minutes: Int

    init(weekday: Int, kind: ShowKind, track: ShowTrack, minutes: Int) {
        self.weekday = weekday
        self.kind = kind
        self.track = track
        self.minutes = minutes
    }

    private enum Keys: String, CodingKey { case weekday, kind, track, minutes, live }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let weekday = c.showInt(.weekday), (1...7).contains(weekday),
              let track = c.showString(.track).flatMap(ShowTrack.init(rawValue:)),
              let minutes = c.showNumber(.minutes), minutes > 0, minutes <= 240 else { throw ShowDecodeError.invalid }
        self.weekday = weekday
        self.track = track
        self.minutes = max(1, Int(minutes.rounded()))
        // The CLINICAL slot table spells a live `live: true`; the API spells it `kind`.
        kind = c.showString(.kind) == "live" || c.showBool(.live) ? .live : .episode
    }
}

/// The weekly clock: always present — the series' own, or the default week.
struct ShowClock: Sendable, Equatable {
    let schedule: [ShowSlot]
    /// "HH:MM".
    let time: String
    let timezone: String

    static let standard = ShowClock(schedule: ShowLogic.defaultSchedule, time: ShowLogic.defaultTime, timezone: ShowLogic.defaultTimeZone)
}

struct ShowSeries: Sendable, Equatable, Decodable {
    let slug: String
    let name: String
    let description: ShowText
    let imageURL: URL?
    let feedURL: String
    let videoFeedURL: String
    let schedule: [ShowSlot]
    let time: String
    let timezone: String

    private enum Keys: String, CodingKey { case slug, name, description, imageUrl, feedUrl, videoFeedUrl, schedule, time, timezone }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let slug = c.showString(.slug), let name = c.showString(.name) else { throw ShowDecodeError.invalid }
        self.slug = slug
        self.name = name
        description = c.showLossy(ShowText.self, .description) ?? ShowText(en: nil)
        imageURL = ShowLogic.httpURL(c.showString(.imageUrl))
        feedURL = c.showText(.feedUrl)
        videoFeedURL = c.showText(.videoFeedUrl)
        var seen = Set<Int>()
        var slots: [ShowSlot] = []
        for slot in c.showObjects(ShowSlot.self, .schedule) where !seen.contains(slot.weekday) {
            seen.insert(slot.weekday)
            slots.append(slot)
        }
        schedule = slots.isEmpty ? ShowLogic.defaultSchedule : slots.sorted { $0.weekday < $1.weekday }
        time = ShowLogic.safeTime(c.showString(.time))
        timezone = ShowLogic.safeTimeZone(c.showString(.timezone))
    }
}

/// A published upcoming episode or live (soonest first in the list).
struct ShowUpcoming: Sendable, Equatable, Decodable, Identifiable {
    let slug: String
    let kind: ShowKind
    let number: Int?
    let title: ShowText
    let track: ShowTrack?
    let startsAt: Date
    let endsAt: Date
    var id: String { slug }

    init(slug: String, kind: ShowKind, number: Int?, title: ShowText, track: ShowTrack?, startsAt: Date, endsAt: Date) {
        self.slug = slug; self.kind = kind; self.number = number; self.title = title
        self.track = track; self.startsAt = startsAt; self.endsAt = endsAt
    }

    private enum Keys: String, CodingKey { case slug, kind, number, title, track, startsAt, endsAt }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let slug = c.showString(.slug), ShowLogic.isSlug(slug),
              let title = c.showTitle(.title), let start = c.showDate(.startsAt) else { throw ShowDecodeError.invalid }
        self.slug = slug
        self.title = title
        startsAt = start
        kind = c.showString(.kind) == "live" ? .live : .episode
        number = c.showInt(.number).flatMap { $0 > 0 ? $0 : nil }
        track = c.showString(.track).flatMap(ShowTrack.init(rawValue:))
        if let end = c.showDate(.endsAt), end > start { endsAt = end } else { endsAt = start.addingTimeInterval(45 * 60) }
    }
}

/// Which pieces an episode carries (the list only says whether they exist).
struct ShowEpisodeHas: Sendable, Equatable, Decodable {
    var research = false
    var article = false
    var guide = false
    var faq = false
    var showNotes = false
    var video = false

    init(research: Bool = false, article: Bool = false, guide: Bool = false, faq: Bool = false, showNotes: Bool = false, video: Bool = false) {
        self.research = research; self.article = article; self.guide = guide
        self.faq = faq; self.showNotes = showNotes; self.video = video
    }

    private enum Keys: String, CodingKey { case research, article, guide, faq, showNotes, video }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        research = c.showBool(.research)
        article = c.showBool(.article)
        guide = c.showBool(.guide)
        faq = c.showBool(.faq)
        showNotes = c.showBool(.showNotes)
        video = c.showBool(.video)
    }
}

/// A published replay (newest first in the list).
struct ShowEpisodeCard: Sendable, Equatable, Decodable, Identifiable {
    let slug: String
    let kind: ShowKind
    let number: Int?
    let title: ShowText
    let summary: ShowText
    let track: ShowTrack?
    let level: Int?
    let startsAt: Date
    let publishedAt: Date?
    let durationSeconds: Int?
    let audioURL: URL?
    let has: ShowEpisodeHas
    var id: String { slug }

    init(slug: String, kind: ShowKind = .episode, number: Int?, title: ShowText, summary: ShowText = ShowText(en: nil), track: ShowTrack?,
         level: Int? = nil, startsAt: Date, publishedAt: Date? = nil, durationSeconds: Int?, audioURL: URL?, has: ShowEpisodeHas) {
        self.slug = slug; self.kind = kind; self.number = number; self.title = title; self.summary = summary; self.track = track
        self.level = level; self.startsAt = startsAt; self.publishedAt = publishedAt; self.durationSeconds = durationSeconds
        self.audioURL = audioURL; self.has = has
    }

    private enum Keys: String, CodingKey { case slug, kind, number, title, summary, track, level, startsAt, publishedAt, durationSeconds, audioUrl, has }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let slug = c.showString(.slug), ShowLogic.isSlug(slug),
              let title = c.showTitle(.title), let start = c.showDate(.startsAt) else { throw ShowDecodeError.invalid }
        self.slug = slug
        self.title = title
        startsAt = start
        kind = c.showString(.kind) == "live" ? .live : .episode
        number = c.showInt(.number).flatMap { $0 > 0 ? $0 : nil }
        summary = c.showLossy(ShowText.self, .summary) ?? ShowText(en: nil)
        track = c.showString(.track).flatMap(ShowTrack.init(rawValue:))
        level = c.showInt(.level).flatMap { (1...5).contains($0) ? $0 : nil }
        publishedAt = c.showDate(.publishedAt)
        durationSeconds = c.showNumber(.durationSeconds).flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        audioURL = ShowLogic.httpURL(c.showString(.audioUrl))
        has = c.showLossy(ShowEpisodeHas.self, .has) ?? ShowEpisodeHas()
    }
}

/// The validated list: what the Library works from.
struct ShowLibrary: Sendable, Equatable {
    let series: ShowSeries?
    let episodes: [ShowEpisodeCard]
    let upcoming: [ShowUpcoming]
    let clock: ShowClock

    init(series: ShowSeries?, episodes: [ShowEpisodeCard], upcoming: [ShowUpcoming]) {
        self.series = series
        self.episodes = episodes.sorted { $0.startsAt > $1.startsAt }
        self.upcoming = upcoming.sorted { $0.startsAt < $1.startsAt }
        clock = series.map { ShowClock(schedule: $0.schedule, time: $0.time, timezone: $0.timezone) } ?? .standard
    }

    /// `GET /api/webinars/library` → the list, or nil for anything unusable (`ok` must be true and `episodes` an array).
    static func decodeList(_ data: Data) -> ShowLibrary? {
        (try? JSON.decoder.decode(ListEnvelope.self, from: data))?.library
    }

    private struct ListEnvelope: Decodable {
        let library: ShowLibrary?
        private enum Keys: String, CodingKey { case ok, series, episodes, upcoming }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            guard c.showBool(.ok), let raw = try? c.decode([ShowLossy<ShowEpisodeCard>].self, forKey: .episodes) else {
                library = nil
                return
            }
            library = ShowLibrary(
                series: c.showLossy(ShowSeries.self, .series),
                episodes: raw.compactMap(\.value),
                upcoming: c.showObjects(ShowUpcoming.self, .upcoming)
            )
        }
    }
}

// MARK: - Episode documents (member view)

/// Both languages of a document; the parser fills a missing side from the other.
struct ShowBilingual<T: Decodable & Sendable & Equatable>: Sendable, Equatable, Decodable {
    let en: T
    let fr: T

    init(en: T, fr: T) {
        self.en = en
        self.fr = fr
    }

    private enum Keys: String, CodingKey { case en, fr }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let e = c.showLossy(T.self, .en)
        let f = c.showLossy(T.self, .fr)
        guard let either = e ?? f else { throw ShowDecodeError.invalid }
        en = e ?? either
        fr = f ?? either
    }

    func pick(_ lang: String) -> T { lang == "fr" ? fr : en }
}

struct ShowChapter: Sendable, Equatable, Decodable {
    /// "hh:mm:ss" or "mm:ss".
    let start: String
    let title: String

    init(start: String, title: String) {
        self.start = start
        self.title = title
    }

    private enum Keys: String, CodingKey { case start, title }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        start = c.showText(.start)
        title = c.showText(.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShowLogic.chapterSeconds(start) != nil, !title.isEmpty else { throw ShowDecodeError.invalid }
    }
}

struct ShowNotes: Sendable, Equatable, Decodable {
    let summary: String
    let chapters: [ShowChapter]
    let keyActions: [String]
    let questions: [String]
    let nextTopics: [String]

    init(summary: String, chapters: [ShowChapter], keyActions: [String], questions: [String] = [], nextTopics: [String] = []) {
        self.summary = summary; self.chapters = chapters; self.keyActions = keyActions
        self.questions = questions; self.nextTopics = nextTopics
    }

    private enum Keys: String, CodingKey { case summary, chapters, keyActions, questions, nextTopics }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        summary = c.showText(.summary)
        chapters = c.showObjects(ShowChapter.self, .chapters)
        keyActions = c.showStrings(.keyActions)
        questions = c.showStrings(.questions)
        nextTopics = c.showStrings(.nextTopics)
        guard !summary.showIsBlank || !chapters.isEmpty || !keyActions.isEmpty else { throw ShowDecodeError.invalid }
    }
}

struct ShowReference: Sendable, Equatable, Decodable {
    let pmid: String
    let title: String
    let journal: String
    let year: Int?
    let authors: String
    let note: String

    init(pmid: String, title: String, journal: String, year: Int?, authors: String, note: String = "") {
        self.pmid = pmid; self.title = title; self.journal = journal; self.year = year; self.authors = authors; self.note = note
    }

    private enum Keys: String, CodingKey { case pmid, title, journal, year, authors, note }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        pmid = (c.showString(.pmid) ?? c.showInt(.pmid).map(String.init) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = c.showText(.title)
        journal = c.showText(.journal)
        year = c.showInt(.year)
        authors = c.showText(.authors)
        note = c.showText(.note)
        guard !title.isEmpty || (!pmid.isEmpty && pmid.allSatisfy(\.isASCIIDigit)) else { throw ShowDecodeError.invalid }
    }
}

struct ShowResearch: Sendable, Equatable, Decodable {
    struct Synthesis: Sendable, Equatable, Decodable {
        var know: [String] = []
        var likely: [String] = []
        var uncertain: [String] = []
        var controversial: [String] = []
        var practical: [String] = []

        init(know: [String] = [], likely: [String] = [], uncertain: [String] = []) {
            self.know = know; self.likely = likely; self.uncertain = uncertain
        }

        private enum Keys: String, CodingKey { case know, likely, uncertain, controversial, practical }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            know = c.showStrings(.know)
            likely = c.showStrings(.likely)
            uncertain = c.showStrings(.uncertain)
            controversial = c.showStrings(.controversial)
            practical = c.showStrings(.practical)
        }

        var isEmpty: Bool { know.isEmpty && likely.isEmpty && uncertain.isEmpty && controversial.isEmpty && practical.isEmpty }
    }

    let questions: [String]
    let claimsToVerify: [String]
    let synthesis: Synthesis
    let references: [ShowReference]

    init(synthesis: Synthesis, references: [ShowReference]) {
        questions = []; claimsToVerify = []
        self.synthesis = synthesis; self.references = references
    }

    private enum Keys: String, CodingKey { case questions, claimsToVerify, synthesis, references }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        questions = c.showStrings(.questions)
        claimsToVerify = c.showStrings(.claimsToVerify)
        synthesis = c.showLossy(Synthesis.self, .synthesis) ?? Synthesis()
        references = c.showObjects(ShowReference.self, .references)
        guard !synthesis.isEmpty || !references.isEmpty else { throw ShowDecodeError.invalid }
    }
}

struct ShowArticle: Sendable, Equatable, Decodable {
    struct Section: Sendable, Equatable, Decodable {
        let heading: String
        let body: String

        init(heading: String, body: String) {
            self.heading = heading
            self.body = body
        }

        private enum Keys: String, CodingKey { case heading, body }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            heading = c.showText(.heading)
            body = c.showText(.body)
            guard !heading.isEmpty || !body.isEmpty else { throw ShowDecodeError.invalid }
        }
    }

    let title: String
    let intro: String
    let sections: [Section]
    let takeaways: [String]
    let references: [String]

    init(title: String, intro: String, sections: [Section], takeaways: [String], references: [String]) {
        self.title = title; self.intro = intro; self.sections = sections; self.takeaways = takeaways; self.references = references
    }

    private enum Keys: String, CodingKey { case title, intro, sections, takeaways, references }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        title = c.showText(.title)
        intro = c.showText(.intro)
        sections = c.showObjects(Section.self, .sections)
        takeaways = c.showStrings(.takeaways)
        references = c.showStrings(.references)
        guard !intro.showIsBlank || !sections.isEmpty else { throw ShowDecodeError.invalid }
    }
}

struct ShowGuide: Sendable, Equatable, Decodable {
    struct Day: Sendable, Equatable, Decodable, Identifiable {
        let day: Int
        let action: String
        var id: Int { day }

        init(day: Int, action: String) {
            self.day = day
            self.action = action
        }

        private enum Keys: String, CodingKey { case day, action }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            guard let day = c.showInt(.day), (1...31).contains(day) else { throw ShowDecodeError.invalid }
            self.day = day
            action = c.showText(.action).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !action.isEmpty else { throw ShowDecodeError.invalid }
        }
    }

    struct Experiment: Sendable, Equatable, Decodable {
        let title: String
        let goal: String
        let days: [Day]

        init(title: String, goal: String, days: [Day]) {
            self.title = title
            self.goal = goal
            self.days = days.sorted { $0.day < $1.day }
        }

        private enum Keys: String, CodingKey { case title, goal, days }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            self.init(title: c.showText(.title), goal: c.showText(.goal), days: c.showObjects(Day.self, .days))
        }
    }

    let summary: String
    let keyActions: [String]
    let experiment: Experiment
    let reflection: [String]
    let references: [String]

    init(summary: String, keyActions: [String], experiment: Experiment, reflection: [String], references: [String] = []) {
        self.summary = summary; self.keyActions = keyActions; self.experiment = experiment
        self.reflection = reflection; self.references = references
    }

    private enum Keys: String, CodingKey { case summary, keyActions, experiment, reflection, references }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        summary = c.showText(.summary)
        keyActions = c.showStrings(.keyActions)
        experiment = c.showLossy(Experiment.self, .experiment) ?? Experiment(title: "", goal: "", days: [])
        reflection = c.showStrings(.reflection)
        references = c.showStrings(.references)
        guard !experiment.days.isEmpty || !summary.showIsBlank || !keyActions.isEmpty else { throw ShowDecodeError.invalid }
    }
}

struct ShowFaq: Sendable, Equatable, Decodable {
    struct Item: Sendable, Equatable, Decodable {
        let question: String
        let answer: String

        init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }

        private enum Keys: String, CodingKey { case question, answer }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            question = c.showText(.question).trimmingCharacters(in: .whitespacesAndNewlines)
            answer = c.showText(.answer)
            guard !question.isEmpty else { throw ShowDecodeError.invalid }
        }
    }

    let items: [Item]

    init(items: [Item]) { self.items = items }

    private enum Keys: String, CodingKey { case items }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        items = c.showObjects(Item.self, .items)
        guard !items.isEmpty else { throw ShowDecodeError.invalid }
    }
}

/// `GET /api/webinars/library/<slug>` — the card plus the member documents (present only once CLINICAL has
/// verified the member's token; an absent document is simply not there).
struct ShowEpisode: Sendable, Equatable, Decodable {
    let card: ShowEpisodeCard
    let member: Bool
    let showNotes: ShowBilingual<ShowNotes>?
    let videoURL: URL?
    let research: ShowBilingual<ShowResearch>?
    let article: ShowBilingual<ShowArticle>?
    let guide: ShowBilingual<ShowGuide>?
    let faq: ShowBilingual<ShowFaq>?

    init(card: ShowEpisodeCard, member: Bool, showNotes: ShowBilingual<ShowNotes>?, videoURL: URL?, research: ShowBilingual<ShowResearch>?,
         article: ShowBilingual<ShowArticle>?, guide: ShowBilingual<ShowGuide>?, faq: ShowBilingual<ShowFaq>?) {
        self.card = card; self.member = member; self.showNotes = showNotes; self.videoURL = videoURL
        self.research = research; self.article = article; self.guide = guide; self.faq = faq
    }

    private enum Keys: String, CodingKey { case member, showNotes, videoUrl, research, article, guide, faq }

    init(from decoder: any Decoder) throws {
        card = try ShowEpisodeCard(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        member = c.showBool(.member)
        showNotes = c.showLossy(ShowBilingual<ShowNotes>.self, .showNotes)
        videoURL = ShowLogic.httpURL(c.showString(.videoUrl))
        research = c.showLossy(ShowBilingual<ShowResearch>.self, .research)
        article = c.showLossy(ShowBilingual<ShowArticle>.self, .article)
        guide = c.showLossy(ShowBilingual<ShowGuide>.self, .guide)
        faq = c.showLossy(ShowBilingual<ShowFaq>.self, .faq)
    }

    /// The episode response → the episode, or nil for anything unusable.
    static func decode(_ data: Data) -> ShowEpisode? {
        (try? JSON.decoder.decode(Envelope.self, from: data))?.episode
    }

    private struct Envelope: Decodable {
        let episode: ShowEpisode?
        private enum Keys: String, CodingKey { case ok, episode }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            episode = c.showBool(.ok) ? c.showLossy(ShowEpisode.self, .episode) : nil
        }
    }
}

/// One experiment mark as `member_lesson_progress` holds it (track_id null, content_slug `show:<slug>:day:<n>`).
struct ShowProgressRow: Sendable, Equatable {
    let contentSlug: String
    let completedAt: Date?
}

// MARK: - Tolerant decoding helpers

enum ShowDecodeError: Error { case invalid }

/// Decodes `T` or nothing — one malformed item never takes its neighbours down.
struct ShowLossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    func showString(_ key: Key) -> String? { try? decodeIfPresent(String.self, forKey: key) }
    func showText(_ key: Key) -> String { showString(key) ?? "" }
    func showBool(_ key: Key) -> Bool { (try? decodeIfPresent(Bool.self, forKey: key)) == true }

    /// A finite JSON number (a string is not a number).
    func showNumber(_ key: Key) -> Double? {
        guard let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite else { return nil }
        return d
    }

    /// A whole JSON number (30 and 30.0 both read as 30; 1.5 reads as nothing).
    func showInt(_ key: Key) -> Int? {
        guard let d = showNumber(key), d == d.rounded(), abs(d) < 1_000_000_000 else { return nil }
        return Int(d)
    }

    func showLossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? { try? decodeIfPresent(T.self, forKey: key) }

    /// Non-blank strings of an array; anything that is not an array of strings reads as [].
    func showStrings(_ key: Key) -> [String] {
        let raw = try? decodeIfPresent([ShowLossy<String>].self, forKey: key)
        return (raw ?? []).compactMap(\.value).filter { !$0.showIsBlank }
    }

    /// The valid objects of an array, the malformed ones dropped one by one.
    func showObjects<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        let raw = try? decodeIfPresent([ShowLossy<T>].self, forKey: key)
        return (raw ?? []).compactMap(\.value)
    }

    func showDate(_ key: Key) -> Date? { showString(key).flatMap(ISO8601.parse) }

    /// `{ en, fr }` where at least one side is non-blank; `en` is filled from `fr` when missing.
    func showTitle(_ key: Key) -> ShowText? {
        guard let t = showLossy(ShowText.self, key) else { return nil }
        let fr = t.fr?.trimmingCharacters(in: .whitespacesAndNewlines).showNonEmpty
        guard let en = t.en?.trimmingCharacters(in: .whitespacesAndNewlines).showNonEmpty ?? fr else { return nil }
        return ShowText(en: en, fr: fr)
    }
}

extension String {
    var showIsBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var showNonEmpty: String? { isEmpty ? nil : self }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
