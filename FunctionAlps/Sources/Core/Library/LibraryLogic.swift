import Foundation

/// Pure library rules — a port of the Expo app's `lib/library/tracks-logic.ts`, `data.ts`
/// (assembly), `collapse.ts` and `thumbnail.ts`. No IO: everything here is unit-testable.
enum LibraryLogic {
    /// OFF since 2026-08-11 ("everything unlocked — we will lock and define the rules later").
    /// Mirrors the members + Expo constant; flip all three together or the surfaces disagree.
    static let sequentialLessonGate = false

    // MARK: Sequential unlock

    /// Index of the first not-done lesson; equals `count` when all are done.
    static func firstOpenIndex(_ lessons: [TrackLesson]) -> Int {
        lessons.firstIndex { !$0.done } ?? lessons.count
    }

    static func lessonAccess(index: Int, first: Int) -> LessonAccess {
        if index < first { return .done }
        if index == first { return .current }
        return sequentialLessonGate ? .locked : .open
    }

    // MARK: Progress

    static func trackPct(done: Int, total: Int) -> Int {
        total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded())
    }

    static func trackState(unlocked: Bool, done: Int, total: Int) -> TrackState {
        if !unlocked { return .locked }
        if total > 0 && done >= total { return .completed }
        if done > 0 { return .inProgress }
        return .new
    }

    // MARK: Gating

    /// Alumni keep the track ("has been a client"); a lapsed trial or `discovery` does not qualify.
    static func isStageSatisfied(required: String?, stage: RelationshipStage) -> Bool {
        guard let required, !required.isEmpty else { return true }
        return [.active, .maintenance, .alumni].contains(stage)
    }

    struct TrackGate: Sendable, Equatable {
        let requiresStage: String?
        let requiresTrackSlug: String?
    }

    /// Unlocked when the stage gate passes and the prerequisite track (if any) is fully
    /// completed. An EMPTY prerequisite never unlocks anything — "nothing to finish is not finished".
    static func isTrackUnlocked(_ gate: TrackGate, stage: RelationshipStage, doneBySlug: [String: Int], totalBySlug: [String: Int]) -> Bool {
        if !isStageSatisfied(required: gate.requiresStage, stage: stage) { return false }
        if let prerequisite = gate.requiresTrackSlug {
            guard let total = totalBySlug[prerequisite] else { return false }
            let done = doneBySlug[prerequisite] ?? 0
            if total == 0 || done < total { return false }
        }
        return true
    }

    static func lockLabel(_ gate: TrackGate, titleBySlug: [String: String]) -> String? {
        if gate.requiresStage != nil {
            return String(localized: "library.lock.consultation", defaultValue: "Unlocks after your consultation")
        }
        if let prerequisite = gate.requiresTrackSlug {
            if let title = titleBySlug[prerequisite] {
                return String(localized: "library.lock.finishTrack", defaultValue: "Finish \(title) to unlock")
            }
            return String(localized: "library.lock.finishPrevious", defaultValue: "Finish the previous track to unlock")
        }
        return nil
    }

    // MARK: STUDIO tag conventions

    static func pairSlug(fromTags tags: [String]) -> String? {
        guard let tag = tags.first(where: { $0.hasPrefix("pair:") }) else { return nil }
        let slug = tag.dropFirst("pair:".count).trimmingCharacters(in: .whitespaces)
        return slug.isEmpty ? nil : slug
    }

    static func isSupplement(tags: [String]) -> Bool { tags.contains("supplement") }

    /// `pillar:<name>` tag, mirroring the members catalog convention.
    static func pillar(fromTags tags: [String]?) -> String {
        guard let tag = (tags ?? []).first(where: { $0.hasPrefix("pillar:") }) else { return "foundations" }
        let name = tag.dropFirst("pillar:".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "foundations" : name
    }

    static func title(fromSlug slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Guards the VALUE, not just the key: only an http(s) URL is a cover the app will fetch.
    static func coverURL(_ raw: String?) -> URL? {
        guard let raw, raw.hasPrefix("http://") || raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    /// Weeks elapsed since the plan start (1-based). Nil without a start date or before it.
    static func weekNumber(startDate: String?, now: Date) -> Int? {
        guard let startDate else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = startDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let days = Int(floor(now.timeIntervalSince(start) / 86_400))
        if days < 0 { return nil }
        return days / 7 + 1
    }

    // MARK: Collapse ("Show all 14 tracks")

    /// Two full rows of the 2-up grid: a collapsed section reads as a complete block.
    static let collapsedCount = 4

    static func visibleItems<T>(_ items: [T], expanded: Bool, limit: Int = collapsedCount) -> [T] {
        if expanded || items.count <= limit { return items }
        return Array(items.prefix(limit))
    }

    /// The toggle's label, or nil when the section fits and needs no toggle at all.
    static func toggleLabel(total: Int, expanded: Bool, noun: String, limit: Int = collapsedCount) -> String? {
        if total <= limit { return nil }
        return expanded
            ? String(localized: "library.showFewer", defaultValue: "Show fewer")
            : String(localized: "library.showAll", defaultValue: "Show all \(total) \(noun)")
    }

    // MARK: Thumbnails

    /// A CDN-resized version of a Supabase public-object URL (`/render/image/public/`), the
    /// originals being 1.8–2.0 MB infographics. Anything else is returned unchanged.
    static func storageThumbnail(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let s = url.absoluteString
        let publicObject = "/storage/v1/object/public/"
        guard s.contains(publicObject) else { return url }
        let base = s.split(separator: "?", maxSplits: 1).first.map(String.init) ?? s
        let rendered = base.replacingOccurrences(of: publicObject, with: "/storage/v1/render/image/public/")
        return URL(string: "\(rendered)?width=\(width)&height=\(height)&resize=contain&quality=70")
    }

    // MARK: Pillar visuals (gradient pairs verbatim from the members catalog)

    static let pillarGradients: [String: (UInt32, UInt32)] = [
        "intestin": (0xDFEAE1, 0xCBDCD0), "gut": (0xDFEAE1, 0xCBDCD0),
        "energie": (0xF4E7CF, 0xECD6B0), "energy": (0xF4E7CF, 0xECD6B0),
        "hormones": (0xF1E3DD, 0xE4CDC4),
        "sommeil": (0xDDE7F1, 0xC6D6EC), "sleep": (0xDDE7F1, 0xC6D6EC),
        "stress": (0xEFE7D9, 0xE1D0B9),
        "inflammation": (0xF7E8DF, 0xEED0BF),
        "nutrition": (0xE7F0E3, 0xD3E4CB),
        "mouvement": (0xE3EDE9, 0xCCE0D8), "movement": (0xE3EDE9, 0xCCE0D8),
        "foundations": (0xDFEAE1, 0xCBDCD0),
    ]

    static func pillarGradient(_ pillar: String?) -> (UInt32, UInt32) {
        pillarGradients[(pillar ?? "").lowercased()] ?? pillarGradients["foundations"]!
    }

    /// The six bundled 16:9 track covers (the Expo app ships the same masters).
    static let bundledCovers: Set<String> = [
        "phase-1-build-your-engine", "phase-2-build-your-stamina", "phase-3-muscle-and-capacity",
        "phase-4-fuel-the-adaptation", "phase-5-recovery-is-training", "phase-6-observe-and-adapt",
    ]

    // MARK: Assembly (the members `loadBundle`, line for line in spirit)

    static func assemble(_ raw: LibraryRaw, stage: RelationshipStage) -> LibraryBundle? {
        guard !raw.tracks.isEmpty else { return nil }
        let access = raw.access ?? .none

        var slugById: [String: String] = [:]
        var titleBySlug: [String: String] = [:]
        for t in raw.tracks { slugById[t.id] = t.slug; titleBySlug[t.slug] = t.title }

        var listBySlug: [String: LibraryListRow] = [:]
        for r in raw.list { listBySlug[r.slug] = r }

        let doneSet = Set(raw.progress.compactMap { p -> String? in
            guard let track = p.trackId else { return nil }
            return "\(track):\(p.contentSlug)"
        })
        var lessonsByTrack: [String: [LibraryRawLesson]] = [:]
        for l in raw.lessons { lessonsByTrack[l.trackId, default: []].append(l) }
        var doneBySlug: [String: Int] = [:]
        var totalBySlug: [String: Int] = [:]
        for t in raw.tracks {
            let lessons = lessonsByTrack[t.id] ?? []
            totalBySlug[t.slug] = lessons.count
            doneBySlug[t.slug] = lessons.filter { doneSet.contains("\(t.id):\($0.contentSlug)") }.count
        }
        let lessonSlugs = Set(raw.lessons.map(\.contentSlug))

        let tracks: [TrackWithProgress] = raw.tracks.map { t in
            let gate = TrackGate(
                requiresStage: t.requiresStage,
                requiresTrackSlug: t.requiresTrackId.flatMap { slugById[$0] }
            )
            let lessons: [TrackLesson] = (lessonsByTrack[t.id] ?? [])
                .sorted { $0.position < $1.position }
                .map { l in
                    let row = listBySlug[l.contentSlug]
                    return TrackLesson(
                        contentSlug: l.contentSlug,
                        position: l.position,
                        title: row?.title ?? title(fromSlug: l.contentSlug),
                        locked: row?.isLocked ?? false,
                        done: doneSet.contains("\(t.id):\(l.contentSlug)"),
                        publishedAt: row?.publishedAt,
                        coverURL: coverURL(row?.coverUrl)
                    )
                }
            let done = doneBySlug[t.slug] ?? 0
            let total = totalBySlug[t.slug] ?? 0
            let unlocked = isTrackUnlocked(gate, stage: stage, doneBySlug: doneBySlug, totalBySlug: totalBySlug)
            return TrackWithProgress(
                id: t.id, slug: t.slug, title: t.title, description: t.description ?? "",
                pillar: t.pillar ?? "foundations", coverStyle: t.coverStyle ?? "", position: t.position,
                lessons: lessons, done: done, total: total,
                pct: trackPct(done: done, total: total),
                state: trackState(unlocked: unlocked, done: done, total: total),
                lockLabel: unlocked ? nil : lockLabel(gate, titleBySlug: titleBySlug)
            )
        }

        let resources: [LibResource] = raw.list
            .filter { !lessonSlugs.contains($0.slug) }
            .map { r in
                LibResource(
                    slug: r.slug,
                    title: r.title ?? title(fromSlug: r.slug),
                    summary: r.summary ?? "",
                    pillar: pillar(fromTags: r.tags),
                    supplement: isSupplement(tags: r.tags ?? []),
                    locked: r.isLocked ?? false,
                    publishedAt: r.publishedAt,
                    coverURL: coverURL(r.coverUrl)
                )
            }

        let prioritySlugs = raw.priorityTrackIds.compactMap { slugById[$0] }
        let plan = raw.plan.map { PlanHeader(title: $0.title ?? "", objectives: raw.planObjectives, startDate: $0.startDate) }

        return LibraryBundle(live: true, stage: stage, access: access, plan: plan, tracks: tracks, prioritySlugs: prioritySlugs, resources: resources)
    }

    // MARK: Reader

    /// A former member drops to `public_free`, so a lock is about ENTITLEMENT, not their practitioner.
    static func lockReason(locked: Bool, stage: RelationshipStage?) -> LockReason? {
        guard locked else { return nil }
        return stage == .alumni ? .membership : .programme
    }

    static func reader(slug: String, bundle: LibraryBundle?, row: LibraryGetRow?) -> ReaderResult? {
        var hit: (track: TrackWithProgress, index: Int)?
        for t in bundle?.tracks ?? [] {
            if let i = t.lessons.firstIndex(where: { $0.contentSlug == slug }) { hit = (t, i); break }
        }
        let tags = row?.tags ?? []
        let pairSlug = pairSlug(fromTags: tags)
        var pair: ReaderResult.Pair?
        if let pairSlug {
            let lessonTitle = bundle?.tracks.flatMap(\.lessons).first { $0.contentSlug == pairSlug }?.title
            let resourceTitle = bundle?.resources.first { $0.slug == pairSlug }?.title
            pair = ReaderResult.Pair(slug: pairSlug, title: lessonTitle ?? resourceTitle ?? title(fromSlug: pairSlug))
        }

        if let hit {
            let track = hit.track, index = hit.index
            let lesson = track.lessons[index]
            // Track-level lock still withholds the body; the per-lesson sequential gate is OFF.
            let gated = track.state == .locked
            let locked = gated || (row?.locked ?? false)
            return ReaderResult(
                kind: .lesson,
                title: row?.title ?? lesson.title,
                pillar: track.pillar,
                bodyMd: locked ? nil : row?.bodyMd,
                locked: locked,
                lockReason: gated ? .programme : lockReason(locked: locked, stage: bundle?.stage),
                supplement: false,
                track: ReaderResult.TrackRef(slug: track.slug, title: track.title, index: index, total: track.lessons.count),
                pair: pair
            )
        }
        guard let row else { return nil }
        let locked = row.locked ?? false
        return ReaderResult(
            kind: .resource,
            title: row.title ?? title(fromSlug: slug),
            pillar: pillar(fromTags: tags),
            bodyMd: locked ? nil : row.bodyMd,
            locked: locked,
            lockReason: lockReason(locked: locked, stage: bundle?.stage),
            supplement: isSupplement(tags: tags),
            track: nil,
            pair: pair
        )
    }

    enum CompleteOutcome: Sendable, Equatable { case ok, notCurrent, error }

    /// Only the FIRST open lesson of an unlocked track may complete — reading ahead is open,
    /// completing ahead is not, so the progress bar stays an honest sequence on both surfaces.
    /// Returns nil when a write is needed (the caller inserts), else the settled outcome.
    static func completionCheck(bundle: LibraryBundle?, trackSlug: String, contentSlug: String) -> CompleteOutcome? {
        guard let track = bundle?.tracks.first(where: { $0.slug == trackSlug }), track.state != .locked else { return .notCurrent }
        guard let index = track.lessons.firstIndex(where: { $0.contentSlug == contentSlug }) else { return .notCurrent }
        if track.lessons[index].done { return .ok }
        if index != firstOpenIndex(track.lessons) { return .notCurrent }
        return nil
    }
}
