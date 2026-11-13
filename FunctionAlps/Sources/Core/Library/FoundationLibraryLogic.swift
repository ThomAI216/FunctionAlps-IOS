import Foundation

/// The address of a YouTube video: the one thing the in-app player needs to play it.
enum YouTubeID {
    static func isYouTubeHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    /// The 11-character id of a `watch?v=`, `youtu.be/`, `/embed/`, `/shorts/` or `/live/` address; nil for anything else
    /// (a search page, a playlist, another host).
    static func parse(_ url: URL) -> String? {
        guard isYouTubeHost(url) else { return nil }
        let host = url.host?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" {
            candidate = parts.first
        } else if parts.first == "watch" {
            candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
        } else if let first = parts.first, ["embed", "shorts", "live", "v"].contains(first), parts.count > 1 {
            candidate = parts[1]
        }
        guard let id = candidate, isValid(id) else { return nil }
        return id
    }

    static func isValid(_ id: String) -> Bool {
        id.count == 11 && id.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128) && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }
}

/// The Library home's rules — pure and tested. Nothing here is a health figure or a health sentence: it sorts, groups
/// and filters what CM OS sends (titles, summaries, tags, the habit cards' resources) and decides what to SHOW.
enum FoundationLibraryLogic {
    static let trackDays = 14

    // MARK: The member's day

    /// The member's track day while they are on the track (days 1…14); nil when they are not, or past day 14 — then
    /// every day is open ("a member not on the track: all days open").
    static func currentDay(_ status: TrackStatus?) -> Int? {
        guard let status, status.state == .active, status.day >= 1, status.day <= min(status.days, trackDays) else { return nil }
        return status.day
    }

    static func phase(day: Int, today: Int?) -> LibraryDayGroup.Phase {
        guard let today else { return .open }
        if day < today { return .past }
        return day == today ? .today : .future
    }

    // MARK: The Foundation Track, day by day

    /// The days that have reads, in order; each with its reads (the day's own read first, then by title) and how many
    /// the member has read. Days outside 1…14 and articles off the track are not part of it.
    static func dayGroups(articles: [LibraryArticle], today: Int?, readSlugs: Set<String>, primary: [Int: String] = [:]) -> [LibraryDayGroup] {
        var byDay: [Int: [LibraryArticle]] = [:]
        for article in articles where article.isFoundationTrack {
            if let day = article.day, (1...trackDays).contains(day) { byDay[day, default: []].append(article) }
        }
        return byDay.keys.sorted().map { day in
            let reads = (byDay[day] ?? []).sorted { left, right in
                let l = left.slug == primary[day], r = right.slug == primary[day]
                if l != r { return l }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
            return LibraryDayGroup(day: day, reads: reads, phase: phase(day: day, today: today), readCount: reads.filter { readSlugs.contains($0.slug) }.count)
        }
    }

    /// "7 of 29 read": the reads read, out of every read on the track.
    static func readTotals(_ groups: [LibraryDayGroup]) -> (read: Int, total: Int) {
        (groups.reduce(0) { $0 + $1.readCount }, groups.reduce(0) { $0 + $1.reads.count })
    }

    /// The day a read opens on when it is still to come for this member; nil when it is open. Only Foundation Track
    /// reads wait for their day — the rest of the library never does.
    static func opensOn(_ article: LibraryArticle, today: Int?) -> Int? {
        guard let today, article.isFoundationTrack, let day = article.day, day > today else { return nil }
        return day
    }

    /// "Read next": the other reads of the same day (the ones not read yet first), then the next day's — never one
    /// that is not open yet.
    static func readNext(after article: LibraryArticle, articles: [LibraryArticle], today: Int?, readSlugs: Set<String>, limit: Int = 2) -> [LibraryArticle] {
        guard article.isFoundationTrack, let day = article.day else { return [] }
        let track = articles.filter { $0.isFoundationTrack && $0.slug != article.slug }
        func reads(on d: Int) -> [LibraryArticle] {
            track.filter { $0.day == d }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        let same = reads(on: day)
        let ordered = same.filter { !readSlugs.contains($0.slug) } + same.filter { readSlugs.contains($0.slug) } + reads(on: day + 1)
        return Array(ordered.filter { opensOn($0, today: today) == nil }.prefix(max(0, limit)))
    }

    // MARK: For your habits

    struct HabitReadSource: Sendable, Equatable {
        let habitTitle: String?
        let slugs: [String]
    }

    /// The reads tied to the member's current habits, titles only: each source's slugs in order, one card per read
    /// (the first habit that names it wins), only reads the library has and that are open for this member.
    static func forYourHabits(sources: [HabitReadSource], articles: [LibraryArticle], today: Int?) -> [LibraryHabitRead] {
        let bySlug = Dictionary(articles.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var out: [LibraryHabitRead] = []
        for source in sources {
            for slug in source.slugs {
                guard let article = bySlug[slug], !seen.contains(slug), opensOn(article, today: today) == nil else { continue }
                seen.insert(slug)
                out.append(LibraryHabitRead(article: article, habitTitle: source.habitTitle))
            }
        }
        return out
    }

    /// The article slugs of a habit card's resources, in order.
    static func articleSlugs(of card: ActionCardRow?) -> [String] {
        ActionCardLogic.links(card?.resources).compactMap { link in
            if case .article(let slug, _) = link { return slug }
            return nil
        }
    }

    // MARK: Watch

    struct VideoSource: Sendable, Equatable {
        let cardId: String?
        let cardTitle: String?
        let links: [ActionCardLink]
    }

    /// The videos of the habits so far, in order, once each. A YouTube address the player cannot read (a search page,
    /// a playlist) is left out.
    static func videos(from sources: [VideoSource]) -> [LibraryVideo] {
        var seen: Set<URL> = []
        var out: [LibraryVideo] = []
        for source in sources {
            for case .video(let url, let title) in source.links {
                if YouTubeID.isYouTubeHost(url), YouTubeID.parse(url) == nil { continue }
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                let name = title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? source.cardTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? String(localized: "library.video.untitled", defaultValue: "Video")
                out.append(LibraryVideo(url: url, title: name, cardId: source.cardId))
            }
        }
        return out
    }

    // MARK: The member's habits

    /// The day the member's track actions are counted up to: today while they are on the track, the last day once
    /// the two weeks are over, none off the track.
    static func actionsThrough(status: TrackStatus?) -> Int? {
        guard let status, status.state == .active, status.day >= 1 else { return nil }
        return min(status.day, trackDays)
    }

    /// The Foundation Track actions the member has had so far: those of the days up to `through` (none off the track).
    static func trackActions(days: [TrackDay], through: Int?) -> [(day: Int, action: TrackAction)] {
        guard let through else { return [] }
        return days.filter { $0.day <= through }.sorted { $0.day < $1.day }.flatMap { day in day.actions.map { (day.day, $0) } }
    }

    /// The same, as what "Practice it" needs to know: the card and the face the day shows.
    static func trackActionRefs(days: [TrackDay], through: Int?) -> [TrackActionRef] {
        trackActions(days: days, through: through).compactMap { entry in
            entry.action.habitBankId.map { TrackActionRef(cardId: $0, face: entry.action.face) }
        }
    }

    /// The member's habits for search: their own and prescribed ones (active), then the track's actions that are not
    /// already one of those.
    static func habits(plan: HabitPlan?, days: [TrackDay], through: Int?, cards: [String: ActionCardRow], locale: String) -> [LibraryHabit] {
        var out: [LibraryHabit] = []
        var cardIds: Set<String> = []
        for habit in plan?.activeHabits ?? [] {
            out.append(LibraryHabit(title: habit.title, moment: habit.slotValue, target: .habit(habit.id)))
            if let card = habit.habitBankId { cardIds.insert(card) }
        }
        for (_, action) in trackActions(days: days, through: through) {
            guard let cardId = action.habitBankId, !cardIds.contains(cardId) else { continue }
            cardIds.insert(cardId)
            let moment: HabitSlot? = switch action.moment {
            case .morning: .morning
            case .midday: .midday
            case .evening: .evening
            case .day: nil
            }
            out.append(LibraryHabit(title: TrackLogic.actionTitle(action, card: cards[cardId], locale: locale), moment: moment,
                                    target: .trackCard(cardId, face: action.face)))
        }
        return out
    }

    // MARK: Practice it

    struct TrackActionRef: Sendable, Equatable {
        let cardId: String
        let face: String
    }

    static func cards(linkingArticle slug: String, in cards: [ActionCardRow]) -> [ActionCardRow] {
        cards.filter { articleSlugs(of: $0).contains(slug) }
    }

    static func cards(linkingVideo url: URL, in cards: [ActionCardRow]) -> [ActionCardRow] {
        cards.filter { card in
            ActionCardLogic.links(card.resources).contains { link in
                if case .video(let u, _) = link { return u == url }
                return false
            }
        }
    }

    /// The habits a read or a video goes with. "Open" when the habit is already in the member's actions (a habit of
    /// theirs, or an action of their track); a small "+ Add" when it is not and the practice lets members add the
    /// card themselves; nothing for a card the member can neither open nor add. The habits already in the actions come first.
    static func practiceItems(cards: [ActionCardRow], plan: HabitPlan?, trackActions: [TrackActionRef], locale: String) -> [LibraryPracticeItem] {
        var items: [LibraryPracticeItem] = []
        for card in cards {
            let cardTitle = ActionCardLogic.pick(card.title, card.titleFr, locale: locale) ?? card.title
            let moment = card.defaultSlot.flatMap(HabitSlot.init(rawValue:))
            if let habit = PlanAccess.habit(for: card.id, in: plan) {
                items.append(LibraryPracticeItem(cardId: card.id, title: habit.title, moment: habit.slotValue ?? moment, action: .open(.habit(habit.id))))
            } else if let ref = trackActions.first(where: { $0.cardId == card.id }) {
                items.append(LibraryPracticeItem(cardId: card.id, title: cardTitle, moment: moment, action: .open(.trackCard(card.id, face: ref.face))))
            } else if card.memberCanAdd == true {
                items.append(LibraryPracticeItem(cardId: card.id, title: cardTitle, moment: moment, action: .add))
            }
        }
        let inActions = items.filter { $0.action != .add }, toAdd = items.filter { $0.action == .add }
        func byTitle(_ list: [LibraryPracticeItem]) -> [LibraryPracticeItem] {
            list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return byTitle(inActions) + byTitle(toAdd)
    }
}

/// On-device search over the library: topics first, then articles, habits and videos.
enum LibrarySearch {
    struct Topic: Sendable, Equatable, Hashable, Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    struct Results: Sendable, Equatable {
        var topics: [Topic] = []
        var articles: [LibraryArticle] = []
        var habits: [LibraryHabit] = []
        var videos: [LibraryVideo] = []
        var isEmpty: Bool { topics.isEmpty && articles.isEmpty && habits.isEmpty && videos.isEmpty }
    }

    /// Lowercased, accents folded: "Énergie" finds "energie".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The tags worth searching: the readable ones. The STUDIO conventions (`day:4`, `minutes:3`, `pillar:x`,
    /// `foundation-track`, `article`…) are structure, not words.
    static func wordTags(_ tags: [String]) -> [String] {
        let structural: Set<String> = ["article", "foundation-track", "quick", "member"]
        return tags.filter { !$0.contains(":") && !structural.contains($0) && LibraryLogic.pillarTopic(fromTags: [$0]) == nil }
            .map { $0.replacingOccurrences(of: "-", with: " ") }
    }

    private static func words(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// How well one token matches a field: a word that starts with it beats a word that merely contains it; 0 = no match.
    private static func match(_ token: String, in text: String) -> Int {
        let folded = fold(text)
        guard folded.contains(token) else { return 0 }
        return words(text).contains { $0.hasPrefix(token) } ? 2 : 1
    }

    /// nil when a token matches none of the fields (every word of the query must be found somewhere).
    private static func score(_ tokens: [String], fields: [(text: String, weight: Int)]) -> Int? {
        var total = 0
        for token in tokens {
            var best = 0
            for field in fields { best = max(best, match(token, in: field.text) * field.weight) }
            if best == 0 { return nil }
            total += best
        }
        return total
    }

    /// Every word a pillar answers to: its key and the English name STUDIO wrote on tracks (sommeil · sleep).
    static func topicWords(_ key: String) -> [String] {
        [key] + LibraryLogic.topicAliases.filter { $0.value == key }.map(\.key)
    }

    static func score(_ article: LibraryArticle, tokens: [String]) -> Int? {
        var fields: [(text: String, weight: Int)] = [(article.title, 6)]
        if let topic = article.topic { fields.append((topic, 4)) }
        if let key = article.topicKey { for word in topicWords(key) { fields.append((word, 4)) } }
        for tag in wordTags(article.tags) { fields.append((tag, 4)) }
        if !article.summary.isEmpty { fields.append((article.summary, 2)) }
        return score(tokens, fields: fields)
    }

    static func results(query: String, articles: [LibraryArticle], habits: [LibraryHabit], videos: [LibraryVideo]) -> Results {
        let tokens = tokens(query)
        guard !tokens.isEmpty else { return Results() }

        // Topics: the pillars the library has, whose word (or key) starts with what was typed.
        var topicKeys: [String] = []
        for article in articles { if let key = article.topicKey, !topicKeys.contains(key) { topicKeys.append(key) } }
        let topics = topicKeys.compactMap { key -> Topic? in
            guard let name = LibraryLogic.topicName(key) else { return nil }
            let spoken = words(name) + topicWords(key).flatMap(words)
            let hit = tokens.allSatisfy { token in spoken.contains { $0.hasPrefix(token) } }
            return hit ? Topic(key: key, name: name) : nil
        }

        let scored = articles.compactMap { article -> (LibraryArticle, Int)? in
            score(article, tokens: tokens).map { (article, $0) }
        }
        let rankedArticles = scored.sorted { l, r in
            if l.1 != r.1 { return l.1 > r.1 }
            let ld = l.0.day ?? Int.max, rd = r.0.day ?? Int.max
            if ld != rd { return ld < rd }
            return l.0.title.localizedCaseInsensitiveCompare(r.0.title) == .orderedAscending
        }.map(\.0)

        let matchedHabits = habits.filter { score(tokens, fields: [($0.title, 1)]) != nil }
        let matchedVideos = videos.filter { score(tokens, fields: [($0.title, 1)]) != nil }
        return Results(topics: topics, articles: rankedArticles, habits: matchedHabits, videos: matchedVideos)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
