import Foundation

// The members library as the phone sees it — the SAME shapes as the Expo app's
// `lib/library/{data,tracks-logic}.ts`, so a track that reads "locked" on the web reads
// "locked" here (two consumers, one rulebook).

struct LibraryAccess: Sendable, Equatable {
    var tracks: Bool
    var foundations: Bool
    var supplements: Bool

    /// Fail closed: no patient, no row, or any error → every section veiled.
    static let none = LibraryAccess(tracks: false, foundations: false, supplements: false)
    static let open = LibraryAccess(tracks: true, foundations: true, supplements: true)
}

/// Where this member stands with the practice (`member_library_stage()`); drives the stage gate only.
enum RelationshipStage: String, Sendable {
    case lead, active, maintenance, alumni, churned
}

struct TrackLesson: Sendable, Equatable, Identifiable {
    let contentSlug: String
    let position: Int
    let title: String
    /// STUDIO tier lock of the underlying card, not the sequential gate.
    let locked: Bool
    let done: Bool
    let publishedAt: String?
    /// The article's own top infographic (`appearance.cover_url`); nil → pillar gradient.
    let coverURL: URL?
    var id: String { contentSlug }
}

enum TrackState: String, Sendable {
    case inProgress, new, completed, locked
}

struct TrackWithProgress: Sendable, Equatable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let pillar: String
    let coverStyle: String
    let position: Int
    let lessons: [TrackLesson]
    let done: Int
    let total: Int
    let pct: Int
    let state: TrackState
    let lockLabel: String?
}

enum LessonAccess: Sendable { case done, current, open, locked }

struct LibResource: Sendable, Equatable, Identifiable {
    let slug: String
    let title: String
    let summary: String
    let pillar: String
    let supplement: Bool
    let locked: Bool
    let publishedAt: String?
    let coverURL: URL?
    var id: String { slug }
}

struct PlanHeader: Sendable, Equatable {
    let title: String
    let objectives: [String]
    let startDate: String?
}

struct LibraryBundle: Sendable, Equatable {
    /// False → live reads failed; screens show the labelled sample instead.
    let live: Bool
    let stage: RelationshipStage
    let access: LibraryAccess
    let plan: PlanHeader?
    let tracks: [TrackWithProgress]
    /// Practitioner-set priority, as track slugs in order. Empty → section hidden.
    let prioritySlugs: [String]
    /// Standalone resources (rows that are not any track's lesson).
    let resources: [LibResource]
}

/// Why an article is withheld — the two are NOT interchangeable to the person reading.
enum LockReason: Sendable, Equatable {
    /// Their practitioner has not opened it yet. Waiting is the right thing to do.
    case programme
    /// The content tier needs an active membership (a former member drops to `public_free`).
    case membership
}

struct ReaderResult: Sendable, Equatable {
    enum Kind: Sendable { case lesson, resource }
    struct TrackRef: Sendable, Equatable { let slug: String; let title: String; let index: Int; let total: Int }
    struct Pair: Sendable, Equatable { let slug: String; let title: String }

    let kind: Kind
    let title: String
    let pillar: String
    let bodyMd: String?
    let locked: Bool
    let lockReason: LockReason?
    let supplement: Bool
    let track: TrackRef?
    let pair: Pair?
}

// MARK: - Raw rows (what CM OS returns; assembled by `LibraryLogic.assemble`)

struct LibraryRawTrack: Sendable, Equatable, Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let pillar: String?
    let coverStyle: String?
    let position: Int
    let requiresStage: String?
    let requiresTrackId: String?
}

struct LibraryRawLesson: Sendable, Equatable, Decodable {
    let trackId: String
    let position: Int
    let contentSlug: String
}

struct LibraryRawProgress: Sendable, Equatable, Decodable {
    let trackId: String?
    let contentSlug: String
}

/// One `member_library_list()` row. `appearance` is free-form jsonb on a table three other
/// projects write to, so only `cover_url` is read, and only when it is an http(s) URL.
struct LibraryListRow: Sendable, Equatable, Decodable {
    let slug: String
    let title: String?
    let summary: String?
    let publishedAt: String?
    let tags: [String]?
    let isLocked: Bool?
    let coverUrl: String?

    private enum CodingKeys: String, CodingKey { case slug, title, summary, publishedAt, tags, isLocked, appearance }
    private struct Appearance: Decodable { let coverUrl: String? }

    init(slug: String, title: String?, summary: String?, publishedAt: String?, tags: [String]?, isLocked: Bool?, coverUrl: String?) {
        self.slug = slug; self.title = title; self.summary = summary; self.publishedAt = publishedAt
        self.tags = tags; self.isLocked = isLocked; self.coverUrl = coverUrl
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        publishedAt = try? c.decodeIfPresent(String.self, forKey: .publishedAt)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
        isLocked = try? c.decodeIfPresent(Bool.self, forKey: .isLocked)
        coverUrl = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance))?.coverUrl
    }
}

struct LibraryRawPlan: Sendable, Equatable, Decodable {
    let id: String
    let title: String?
    let startDate: String?
}

/// `member_library_get(p_slug)` — the body is withheld server-side on lock.
struct LibraryGetRow: Sendable, Equatable, Decodable {
    let title: String?
    let tags: [String]?
    let bodyMd: String?
    let locked: Bool?
}

/// Everything the library needs, read in one go under the member's own session. Each
/// optional part fails soft (empty / nil) so one bad read never blanks the tab; only the
/// track catalog is required.
struct LibraryRaw: Sendable, Equatable {
    var tracks: [LibraryRawTrack] = []
    var lessons: [LibraryRawLesson] = []
    var progress: [LibraryRawProgress] = []
    var list: [LibraryListRow] = []
    /// nil = no row (or the read failed) → fail closed.
    var access: LibraryAccess? = nil
    var priorityTrackIds: [String] = []
    var plan: LibraryRawPlan? = nil
    var planObjectives: [String] = []
}
