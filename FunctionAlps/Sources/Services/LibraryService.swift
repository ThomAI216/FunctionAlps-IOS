import Foundation

/// The library as a second consumer of the members catalog — same tables, same RPCs, the
/// member's own session. Everything fails soft to nil so the screens fall back to the
/// labelled sample library; the veil flags alone fail CLOSED (see `LibraryLogic.assemble`).
struct LibraryService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let now: @Sendable () -> Date
    private let coverCache = TopicCoverCache()
    private let catalogCache = CatalogCache()

    init(backend: any FunctionAlpsBackend, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    /// Fail-closed to `.lead` on any error or unknown value: a gate that cannot answer must lock.
    func stage() async -> RelationshipStage {
        guard let raw = try? await backend.libraryStage() else { return .lead }
        return raw == .active || raw == .alumni ? raw : .lead
    }

    func bundle(patientId: String) async -> LibraryBundle? {
        async let covers = topicCovers()
        let current = await stage()
        guard let raw = try? await backend.libraryRaw(patientId: patientId) else { return nil }
        return LibraryLogic.assemble(raw, stage: current, covers: await covers)
    }

    /// The topic covers, read once per app run and reused by every screen. Fails soft to an empty map
    /// (the gradients show); a failed read is not remembered, so the next library load tries again.
    func topicCovers() async -> [String: URL] {
        if let cached = await coverCache.map { return cached }
        guard let rows = try? await backend.libraryTopicCovers() else { return [:] }
        let map = LibraryLogic.topicCovers(rows)
        await coverCache.store(map)
        return map
    }

    /// The Library home's whole read, once, under the member's own session: the list (`member_library_list`), which
    /// of it the member has read (`member_lesson_progress`), and the track bundle the prescribed block uses (nil
    /// when the track catalog is empty). Throws only when the catalog read itself fails — the screen then says so.
    func catalog(patientId: String) async throws -> LibraryCatalog {
        async let covers = topicCovers()
        let current = await stage()
        let raw = try await backend.libraryRaw(patientId: patientId)
        let bundle = LibraryLogic.assemble(raw, stage: current, covers: await covers)
        let articles = raw.list.map(LibraryArticle.init(row:))
        await catalogCache.store(articles)
        return LibraryCatalog(articles: articles, readSlugs: Set(raw.progress.map(\.contentSlug)), bundle: bundle)
    }

    /// The list the Library home read last, or a fresh read when the screen is reached without it (a link).
    func articles(patientId: String) async -> [LibraryArticle]? {
        if let cached = await catalogCache.articles { return cached }
        return try? await catalog(patientId: patientId).articles
    }

    /// The slugs this member has read (opened a standalone read, marked one, or finished a lesson).
    func readSlugs(patientId: String) async -> Set<String>? {
        try? await backend.openedLibrarySlugs(patientId: patientId)
    }

    /// "Mark as read": the same row an open of a standalone read writes (`member_lesson_progress`, no track).
    /// A read already recorded is not written twice. Returns false when the write failed.
    func markRead(patientId: String, slug: String, alreadyRead: Bool) async -> Bool {
        if alreadyRead { return true }
        do {
            try await backend.insertLessonProgress(patientId: patientId, trackId: nil, contentSlug: slug)
            return true
        } catch AppError.validation(let message) where message.contains("23505") || message.lowercased().contains("duplicate") {
            return true
        } catch {
            Log.data.error("library.markRead: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func reader(slug: String, patientId: String) async -> ReaderResult? {
        if slug.hasPrefix("demo-") { return LibraryDemo.reader(slug: slug) }
        let loaded = await bundle(patientId: patientId)
        let row = try? await backend.libraryItem(slug: slug)
        guard var result = LibraryLogic.reader(slug: slug, bundle: loaded, row: row) else { return nil }
        // The list row carries what the reader's header needs (summary, day, reading time): the home read it already.
        let cached = await catalogCache.articles?.first { $0.slug == slug }
        let fromRow = row.map {
            LibraryArticle(slug: slug, title: $0.title ?? LibraryLogic.title(fromSlug: slug), summary: $0.summary ?? "", tags: $0.tags ?? [], locked: $0.locked ?? false)
        }
        if var article = cached ?? fromRow {
            if article.summary.isEmpty, let summary = row?.summary {
                article = LibraryArticle(slug: article.slug, title: article.title, summary: summary, tags: article.tags, locked: article.locked)
            }
            result.article = article
        }
        return result
    }

    /// An item's title alone (Home's "Today's read" card); nil when the library has no such item.
    func itemTitle(slug: String) async throws -> String? {
        try await backend.libraryItem(slug: slug)?.title
    }

    /// Same rule as the members `completeLesson`: only the first open lesson of an unlocked track.
    func completeLesson(patientId: String, trackSlug: String, contentSlug: String) async -> LibraryLogic.CompleteOutcome {
        let loaded = await bundle(patientId: patientId)
        if let settled = LibraryLogic.completionCheck(bundle: loaded, trackSlug: trackSlug, contentSlug: contentSlug) { return settled }
        guard let track = loaded?.tracks.first(where: { $0.slug == trackSlug }) else { return .notCurrent }
        do {
            try await backend.insertLessonProgress(patientId: patientId, trackId: track.id, contentSlug: contentSlug)
            return .ok
        } catch AppError.validation(let message) where message.contains("23505") || message.lowercased().contains("duplicate") {
            return .ok // the unique constraint (PostgREST 409 → validation): already done
        } catch {
            Log.data.error("library.complete: \(String(describing: error), privacy: .public)")
            return .error
        }
    }

    /// A standalone-resource open feeds the foundations bar and streak on the members side too.
    func recordResourceOpen(patientId: String, slug: String) async {
        try? await backend.insertLessonProgress(patientId: patientId, trackId: nil, contentSlug: slug)
    }

    func weekNumber(startDate: String?) -> Int? {
        LibraryLogic.weekNumber(startDate: startDate, now: now())
    }
}

/// Holds the topic-cover map for the app run (covers change only in STUDIO, and a swap is a new URL).
private actor TopicCoverCache {
    private(set) var map: [String: URL]?
    func store(_ value: [String: URL]) { map = value }
}

/// The last list the Library home read, so the reader can show a read's summary without another round trip.
private actor CatalogCache {
    private(set) var articles: [LibraryArticle]?
    func store(_ value: [LibraryArticle]) { articles = value }
}
