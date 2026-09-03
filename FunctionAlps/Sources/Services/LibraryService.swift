import Foundation

/// The library as a second consumer of the members catalog — same tables, same RPCs, the
/// member's own session. Everything fails soft to nil so the screens fall back to the
/// labelled sample library; the veil flags alone fail CLOSED (see `LibraryLogic.assemble`).
struct LibraryService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let now: @Sendable () -> Date

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
        let stage = await stage()
        guard let raw = try? await backend.libraryRaw(patientId: patientId) else { return nil }
        return LibraryLogic.assemble(raw, stage: stage)
    }

    func reader(slug: String, patientId: String) async -> ReaderResult? {
        if slug.hasPrefix("demo-") { return LibraryDemo.reader(slug: slug) }
        let bundle = await bundle(patientId: patientId)
        let row = try? await backend.libraryItem(slug: slug)
        return LibraryLogic.reader(slug: slug, bundle: bundle, row: row)
    }

    /// Same rule as the members `completeLesson`: only the first open lesson of an unlocked track.
    func completeLesson(patientId: String, trackSlug: String, contentSlug: String) async -> LibraryLogic.CompleteOutcome {
        let bundle = await bundle(patientId: patientId)
        if let settled = LibraryLogic.completionCheck(bundle: bundle, trackSlug: trackSlug, contentSlug: contentSlug) { return settled }
        guard let track = bundle?.tracks.first(where: { $0.slug == trackSlug }) else { return .notCurrent }
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
