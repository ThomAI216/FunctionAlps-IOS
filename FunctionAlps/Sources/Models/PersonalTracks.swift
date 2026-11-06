import Foundation

/// One step of a personal mini track (`patient_track_lessons`, CLINICAL migration 283). Two kinds share the table:
/// a library item (opens in the reader) and an action card (`content_slug = 'action:<habit_bank_id>'`, offered to
/// the member on its card, never opened as an article).
struct PersonalTrackItem: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable, Hashable {
        case article(String)   // library slug
        case action(String)    // habit_bank id
    }
    let position: Int
    let kind: Kind

    var id: String {
        switch kind {
        case .article(let slug): "article:\(slug)"
        case .action(let id): "action:\(id)"
        }
    }

    var slug: String? { if case .article(let s) = kind { return s } else { return nil } }

    /// The wire form of the lesson row: a set `habit_bank_id` wins over the slug; an `action:` slug without an id
    /// still reads as an action (the id is the slug's tail); an empty row is no item.
    static func from(position: Int, contentSlug: String?, habitBankId: String?) -> PersonalTrackItem? {
        if let habitBankId, !habitBankId.isEmpty { return PersonalTrackItem(position: position, kind: .action(habitBankId)) }
        guard let slug = contentSlug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty else { return nil }
        if slug.hasPrefix("action:") {
            let id = String(slug.dropFirst("action:".count))
            return id.isEmpty ? nil : PersonalTrackItem(position: position, kind: .action(id))
        }
        return PersonalTrackItem(position: position, kind: .article(slug))
    }
}

/// A mini track the practice built for this member (`patient_tracks` with `source_track_id` null).
struct PersonalTrack: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    /// The practitioner's personal message; empty when none.
    let intro: String
    let createdAt: Date
    /// The `patient_messages` row it was sent with.
    let originMessageId: String?
    let items: [PersonalTrackItem]
}

/// Raw rows (the member-readable columns; RLS keeps to own, active, approved).
struct PersonalTrackRow: Decodable, Sendable {
    let id: String
    let title: String?
    let introMd: String?
    let createdAt: Date
    let originMessageId: String?
}

struct PersonalTrackLessonRow: Decodable, Sendable {
    let patientTrackId: String
    let position: Int?
    let contentSlug: String?
    let habitBankId: String?
}

/// What a message shows for the track it carried: "<title> · N resources".
struct PersonalTrackSummary: Sendable, Equatable {
    let id: String
    let title: String
    let itemCount: Int
    /// One flag per item in order (true = an action card), for the little tiles on the message card.
    var actionFlags: [Bool] = []
}

enum PersonalTrackLogic {
    /// Tracks as the member sees them: newest first (a tie keeps title order), lessons by position, a lesson row
    /// that is empty dropped, an untitled track dropped (there is nothing to name it by).
    static func assemble(tracks: [PersonalTrackRow], lessons: [PersonalTrackLessonRow]) -> [PersonalTrack] {
        let byTrack = Dictionary(grouping: lessons, by: \.patientTrackId)
        return tracks.compactMap { row -> PersonalTrack? in
            let title = (row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var seen = Set<String>()
            let items = (byTrack[row.id] ?? [])
                .sorted { ($0.position ?? .max) < ($1.position ?? .max) }
                .enumerated()
                .compactMap { index, l in PersonalTrackItem.from(position: l.position ?? index, contentSlug: l.contentSlug, habitBankId: l.habitBankId) }
                .filter { seen.insert($0.id).inserted }
            return PersonalTrack(id: row.id, title: title, intro: (row.introMd ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 createdAt: row.createdAt, originMessageId: row.originMessageId, items: items)
        }
        .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.title < $1.title }
    }

    /// Articles of the track the member has opened (a library open leaves a `member_lesson_progress` row by slug).
    /// Actions have no open state: they are offered, and adding one to the plan is the member's own act.
    static func openedCount(_ track: PersonalTrack, openedSlugs: Set<String>) -> Int {
        track.items.filter { isOpened($0, openedSlugs: openedSlugs) }.count
    }

    static func isOpened(_ item: PersonalTrackItem, openedSlugs: Set<String>) -> Bool {
        item.slug.map(openedSlugs.contains) ?? false
    }

    /// Slugs of the articles of a track not opened yet.
    static func unopened(_ track: PersonalTrack, openedSlugs: Set<String>) -> [String] {
        track.items.compactMap(\.slug).filter { !openedSlugs.contains($0) }
    }

    /// The Library badge and Home nudge: sent articles never opened. A slug already counted from the loose sends
    /// (`alreadyCounted`) is not counted twice.
    static func unopenedCount(_ tracks: [PersonalTrack], openedSlugs: Set<String>, alreadyCounted: Set<String>) -> Int {
        var seen = alreadyCounted
        var n = 0
        for track in tracks {
            for slug in unopened(track, openedSlugs: openedSlugs) where seen.insert(slug).inserted { n += 1 }
        }
        return n
    }

    /// The summary the message of `track.originMessageId` shows (one track per message: the newest wins).
    static func summaries(_ tracks: [PersonalTrack]) -> [String: PersonalTrackSummary] {
        var out: [String: PersonalTrackSummary] = [:]
        for t in tracks.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let mid = t.originMessageId, out[mid] == nil else { continue }
            out[mid] = PersonalTrackSummary(id: t.id, title: t.title, itemCount: t.items.count,
                                            actionFlags: t.items.map { if case .action = $0.kind { true } else { false } })
        }
        return out
    }

    /// The start of the intro for a card, collapsed to one paragraph; nil when there is none.
    static func introPreview(_ intro: String, limit: Int = 110) -> String? {
        let flat = intro.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "1 resource" / "N resources" (never "1 resources").
    static func countLabel(_ n: Int) -> String {
        n == 1 ? String(localized: "personalTrack.count.one", defaultValue: "1 resource")
               : String(localized: "personalTrack.count", defaultValue: "\(n) resources")
    }

    /// "<title> · N resources" under the message.
    static func messageLabel(_ s: PersonalTrackSummary) -> String { "\(s.title) · \(countLabel(s.itemCount))" }

    /// The loose sends only: an item a personal track of the same message already holds is shown in the track.
    static func looseResources(_ resources: [MessageResource], tracks: [PersonalTrack]) -> [MessageResource] {
        var held = Set<String>()
        for t in tracks { if let mid = t.originMessageId { for s in t.items.compactMap(\.slug) { held.insert("\(mid)|\(s)") } } }
        return resources.filter { !held.contains("\($0.messageId)|\($0.slug)") }
    }
}

/// Everything the track page draws: the track, the titles resolved for its items (`slug` for an article,
/// `action:<id>` for a card), and the slugs the member has opened.
struct PersonalTrackPage: Sendable, Equatable {
    let track: PersonalTrack
    let titles: [String: String]
    let openedSlugs: Set<String>

    func title(for item: PersonalTrackItem) -> String {
        switch item.kind {
        case .article(let slug): titles[slug] ?? PersonalTrackLogic.fallbackTitle(slug)
        case .action(let id): titles["action:" + id] ?? String(localized: "personalTrack.action.untitled", defaultValue: "An action for you")
        }
    }
}

extension PersonalTrackLogic {
    /// "post-meal-walking" → "Post meal walking", for an item whose title could not be read.
    static func fallbackTitle(_ slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

// MARK: The path (the redesigned track page)

/// A step of the path: one of the track's items, or the closing check-in with the practitioner.
enum PersonalTrackStepKind: Sendable, Equatable {
    case item(PersonalTrackItem)
    case checkIn
}

enum PersonalTrackStepState: Sendable, Equatable {
    case done, current, upcoming
}

struct PersonalTrackStep: Sendable, Equatable, Identifiable {
    /// 1-based, the number in the step's dot.
    let number: Int
    let kind: PersonalTrackStepKind
    let state: PersonalTrackStepState

    var id: String {
        switch kind {
        case .item(let item): item.id
        case .checkIn: "check-in"
        }
    }
}

extension PersonalTrackLogic {
    /// An article is done when opened (its `member_lesson_progress` row, by slug); an action when the member's plan
    /// holds a habit made from its card.
    static func isDone(_ item: PersonalTrackItem, openedSlugs: Set<String>, planCardIds: Set<String>) -> Bool {
        switch item.kind {
        case .article(let slug): openedSlugs.contains(slug)
        case .action(let id): planCardIds.contains(id)
        }
    }

    /// (done, total) over the track's items; the check-in is not counted.
    static func progress(_ track: PersonalTrack, openedSlugs: Set<String>, planCardIds: Set<String>) -> (done: Int, total: Int) {
        (track.items.filter { isDone($0, openedSlugs: openedSlugs, planCardIds: planCardIds) }.count, track.items.count)
    }

    /// The path, in `position` order, closed by the check-in. Current = the first item not done and not put off with
    /// "Later"; when only put-off items remain, the first of them; when every item is done, the check-in. The check-in
    /// is never done (it is a prompt to write, not something the app can see). No items, no path.
    static func steps(_ track: PersonalTrack, openedSlugs: Set<String>, planCardIds: Set<String>, deferred: Set<String> = []) -> [PersonalTrackStep] {
        guard !track.items.isEmpty else { return [] }
        let items = track.items.sorted { $0.position < $1.position }
        let done = items.map { isDone($0, openedSlugs: openedSlugs, planCardIds: planCardIds) }
        let open = items.indices.filter { !done[$0] }
        let currentIndex = open.first { !deferred.contains(items[$0].id) } ?? open.first
        var out: [PersonalTrackStep] = items.enumerated().map { index, item in
            PersonalTrackStep(number: index + 1, kind: .item(item),
                              state: done[index] ? .done : (index == currentIndex ? .current : .upcoming))
        }
        out.append(PersonalTrackStep(number: items.count + 1, kind: .checkIn, state: open.isEmpty ? .current : .upcoming))
        return out
    }

    /// "Later" is offered on the current action only while another step is still open to move on to.
    static func canPutOff(_ step: PersonalTrackStep, in steps: [PersonalTrackStep], deferred: Set<String>) -> Bool {
        guard step.state == .current, case .item(let item) = step.kind, case .action = item.kind else { return false }
        return steps.contains { s in
            guard s.id != step.id, s.state == .upcoming, case .item(let other) = s.kind else { return false }
            return !deferred.contains(other.id)
        }
    }

    /// "Curated for you · 4 Nov" (the date the track was sent, in the reader's language and calendar).
    static func heroEyebrow(sentAt: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return PathwayCopy.eyebrow + " · " + f.string(from: sentAt)
    }

    /// "1 of 3 done".
    static func progressLabel(done: Int, total: Int) -> String {
        String(localized: "personalTrack.progress", defaultValue: "\(done) of \(total) done")
    }

    /// 0...1 for the thin bar.
    static func progressFraction(done: Int, total: Int) -> Double {
        total <= 0 ? 0 : min(1, max(0, Double(done) / Double(total)))
    }

    /// "<N> picks" on the message card.
    static func picksLabel(_ n: Int) -> String {
        n == 1 ? String(localized: "personalTrack.picks.one", defaultValue: "1 pick")
               : String(localized: "personalTrack.picks", defaultValue: "\(n) picks")
    }

    /// The first letters of a name for the initials disc ("Anna Keller" → "AK"); nil when there is no usable name.
    static func initials(_ name: String?) -> String? {
        let letters = (name ?? "").split(whereSeparator: { $0.isWhitespace }).compactMap { $0.first(where: \.isLetter) }
        guard !letters.isEmpty else { return nil }
        return String(letters.prefix(2)).uppercased()
    }
}
