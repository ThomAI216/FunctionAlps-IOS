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
            out[mid] = PersonalTrackSummary(id: t.id, title: t.title, itemCount: t.items.count)
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
