import Foundation

/// The library as a second consumer of the members catalog — same tables, same RPCs, the
/// member's own session. Everything fails soft to nil so the screens fall back to the
/// labelled sample library; the veil flags alone fail CLOSED (see `LibraryLogic.assemble`).
struct LibraryService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let now: @Sendable () -> Date
    private let coverCache = TopicCoverCache()

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

    func reader(slug: String, patientId: String) async -> ReaderResult? {
        if slug.hasPrefix("demo-") { return LibraryDemo.reader(slug: slug) }
        let loaded = await bundle(patientId: patientId)
        let row = try? await backend.libraryItem(slug: slug)
        return LibraryLogic.reader(slug: slug, bundle: loaded, row: row)
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
