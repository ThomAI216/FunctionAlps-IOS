import Foundation

// The Library home as the phone lays it out (Thomas, 2026-11-10): the Foundation Track day by day, the reads tied to
// the member's habits, the videos, search. Everything here is a value; the rules live in `FoundationLibraryLogic`.

/// One `member_library_list()` row as the Library reads it. The STUDIO tags are the whole contract:
/// `day:N` (the Foundation Track day), `minutes:N` (reading time), `foundation-track`, and the pillar tag.
struct LibraryArticle: Sendable, Equatable, Hashable, Identifiable {
    let slug: String
    let title: String
    let summary: String
    let tags: [String]
    let locked: Bool

    var id: String { slug }

    init(slug: String, title: String, summary: String = "", tags: [String] = [], locked: Bool = false) {
        self.slug = slug; self.title = title; self.summary = summary; self.tags = tags; self.locked = locked
    }

    init(row: LibraryListRow) {
        self.init(
            slug: row.slug,
            title: row.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? LibraryLogic.title(fromSlug: row.slug),
            summary: row.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            tags: row.tags ?? [],
            locked: row.isLocked ?? false
        )
    }

    /// The Foundation Track day this read belongs to (`day:N`).
    var day: Int? { Self.number(in: tags, prefix: "day:") }
    /// Reading time in minutes (`minutes:N`).
    var minutes: Int? { Self.number(in: tags, prefix: "minutes:") }
    var isFoundationTrack: Bool { tags.contains("foundation-track") }
    /// The pillar key of the read (`sommeil`, `nutrition`, `mouvement`, `stress`, …), nil without a pillar tag.
    var topicKey: String? { LibraryLogic.pillarTopic(fromTags: tags) }
    /// The pillar as a topic word ("Sleep"); nil without one.
    var topic: String? { topicKey.flatMap(LibraryLogic.topicName) }

    private static func number(in tags: [String], prefix: String) -> Int? {
        for tag in tags where tag.hasPrefix(prefix) {
            if let n = Int(tag.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)), n > 0 { return n }
        }
        return nil
    }
}

/// Everything the Library home reads in one go: the list, which of it the member has read, and (when the track
/// catalog could be assembled) the bundle the prescribed block still uses.
struct LibraryCatalog: Sendable, Equatable {
    var articles: [LibraryArticle]
    /// `member_lesson_progress.content_slug` of this member: a read the member opened or marked.
    var readSlugs: Set<String>
    var bundle: LibraryBundle?
}

/// One day of the Foundation Track on the Library: every read of the day, and where the member stands on it.
struct LibraryDayGroup: Sendable, Equatable, Identifiable {
    enum Phase: Sendable, Equatable { case past, today, future, open }
    enum Status: Sendable, Equatable {
        case read
        case partial(done: Int, total: Int)
        case unread
        case new
        case locked(opensOnDay: Int)
    }

    let day: Int
    let reads: [LibraryArticle]
    let phase: Phase
    let readCount: Int

    var id: Int { day }
    var allRead: Bool { !reads.isEmpty && readCount >= reads.count }
    /// Soft-locked, never hard-locked: a future day shows its titles but cannot be opened.
    var isOpenable: Bool { phase != .future }

    var status: Status {
        if phase == .future { return .locked(opensOnDay: day) }
        if allRead { return .read }
        if readCount > 0 { return .partial(done: readCount, total: reads.count) }
        return phase == .today ? .new : .unread
    }
}

/// A video among the habits' resources (`habit_bank.resources` `{kind: "video", url, title}`).
struct LibraryVideo: Sendable, Hashable, Identifiable {
    let url: URL
    let title: String
    /// The `habit_bank` card it belongs to, for "Practice it".
    var cardId: String? = nil

    var id: String { url.absoluteString }
    var youtubeID: String? { YouTubeID.parse(url) }
    var isYouTube: Bool { youtubeID != nil }
}

/// Where a habit opens: one of the member's habits (its card), or a Foundation Track action's card.
enum LibraryHabitTarget: Sendable, Hashable {
    case habit(String)
    case trackCard(String, face: String)
}

/// One of the member's habits, as search and "Practice it" know it.
struct LibraryHabit: Sendable, Equatable, Hashable, Identifiable {
    let title: String
    let moment: HabitSlot?
    let target: LibraryHabitTarget

    var id: String {
        switch target {
        case .habit(let id): "habit:\(id)"
        case .trackCard(let card, _): "card:\(card)"
        }
    }
}

/// A read of "For your habits", with the habit it goes with.
struct LibraryHabitRead: Sendable, Equatable, Identifiable {
    let article: LibraryArticle
    let habitTitle: String?
    var id: String { article.slug }
}

/// One line of "Practice it" on a read or a video.
struct LibraryPracticeItem: Sendable, Equatable, Identifiable {
    enum Action: Sendable, Equatable {
        /// The habit is in the member's actions: open it.
        case open(LibraryHabitTarget)
        /// Not in the actions yet, and the practice lets members add it themselves.
        case add
    }

    let cardId: String
    let title: String
    let moment: HabitSlot?
    let action: Action
    var id: String { cardId }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
