import Foundation

/// The fail-soft sample library — "the screen never reads as an empty library". Shown ONLY when
/// the live reads fail (no session, offline, RLS misconfig); titles are the real seeded catalog's.
/// Veil flags are never mocked: a real session always gets the real `member_library_access` row.
enum LibraryDemo {
    private static func track(_ n: Int, _ slug: String, _ title: String, _ description: String, _ pillar: String, _ lessons: [String], done: Int) -> TrackWithProgress {
        let items = lessons.enumerated().map { i, t in
            TrackLesson(contentSlug: "demo-\(slug)-\(i + 1)", position: i + 1, title: t, locked: false, done: i < done, publishedAt: nil, coverURL: nil)
        }
        return TrackWithProgress(
            id: "demo-\(slug)", slug: "demo-\(slug)", title: title, description: description, pillar: pillar,
            coverStyle: "sprout", position: n, lessons: items, done: done, total: lessons.count,
            pct: LibraryLogic.trackPct(done: done, total: lessons.count),
            state: done > 0 ? .inProgress : .new, lockLabel: nil
        )
    }

    static let tracks: [TrackWithProgress] = [
        track(1, "gut-reset", "Gut Reset", "Understand your gut, calm it, and rebuild it: the protocol that underpins everything else.", "intestin",
              ["Understand your gut", "Calm the fire", "Feedback and self-tracking", "Rebuild the terrain", "Feed the good guys", "Keep it"], done: 2),
        track(2, "build-your-engine", "Build Your Engine", "The systems that decide how well you produce energy, sustain effort and recover.", "energie",
              ["How it all works together", "Signals create adaptation"], done: 0),
        track(3, "sleep-repair", "Sleep Repair", "Rebuild deep, continuous sleep: rhythm, evening routine, and the habits that hold it in place.", "sommeil",
              ["Your sleep architecture", "The evening ramp", "Light, timing, temperature", "When sleep breaks", "Keep it"], done: 0),
        track(4, "strength-capacity", "Strength & Capacity", "Make your training more effective and build capacity that lasts.", "mouvement",
              ["Signals create adaptation", "Make training work better", "Progressive overload", "Recovery is training", "Capacity for life", "Keep it"], done: 0),
    ]

    static let resources: [LibResource] = [
        LibResource(slug: "demo-post-meal-walking", title: "Post-Meal Walking", summary: "A simple habit for glucose, digestion, energy and recovery", pillar: "intestin", supplement: false, locked: false, publishedAt: nil, coverURL: nil),
        LibResource(slug: "demo-breathing-exercises", title: "Breathing Exercises", summary: "A simple tool to regulate your nervous system", pillar: "foundations", supplement: false, locked: false, publishedAt: nil, coverURL: nil),
        LibResource(slug: "demo-nsdr", title: "NSDR / Yoga Nidra", summary: "Deep recovery for your nervous system", pillar: "sommeil", supplement: false, locked: false, publishedAt: nil, coverURL: nil),
        LibResource(slug: "demo-magnesium", title: "Magnesium", summary: "What it does, who runs low, and how to take it", pillar: "nutrition", supplement: true, locked: false, publishedAt: nil, coverURL: nil),
        LibResource(slug: "demo-omega-3", title: "Omega-3", summary: "The anti-inflammatory foundation, dosed properly", pillar: "nutrition", supplement: true, locked: false, publishedAt: nil, coverURL: nil),
    ]

    /// Sections OPEN here — there is no real member data behind them to protect.
    static let bundle = LibraryBundle(live: false, stage: .lead, access: .open, plan: nil, tracks: tracks, prioritySlugs: [tracks[0].slug], resources: resources)

    static let readerBody = """
    Your body already tells you whether the protocol is working. This is how to listen on purpose.

    ## The weekly loop

    The rhythm never changes: **action, response, interpretation, adjustment.** You act for a week, notice what your body sends back, decide what it means, and adjust one thing.

    ![Micronutrient tracking · track representative days, identify repeated gaps, improve food first, review](https://ndojytvvlvlbgtodujkf.supabase.co/storage/v1/object/public/content-public/library/micronutrient-tracking/03_micronutrient_tracking.png)

    ## How to read your week

    - **Green** · energised, sleep stable, digestion good. Continue, or progress slowly.
    - **Yellow** · more tired, soreness lingering, sleep slightly disrupted. Observe, adjust slightly.
    - **Red** · sleep worsening, drained for days, pain appearing. Reduce, modify or pause.

    ## Do this week

    1. Rate every dinner's reaction for 7 days. One tap each.
    2. At the end of the week, read your green/yellow/red pattern.
    3. Bring the pattern to your next check-in · it is the conversation.
    """

    static func reader(slug: String) -> ReaderResult? {
        for t in tracks {
            if let i = t.lessons.firstIndex(where: { $0.contentSlug == slug }) {
                return ReaderResult(kind: .lesson, title: t.lessons[i].title, pillar: t.pillar, bodyMd: readerBody, locked: false, lockReason: nil, supplement: false,
                                    track: ReaderResult.TrackRef(slug: t.slug, title: t.title, index: i, total: t.lessons.count), pair: nil)
            }
        }
        if let r = resources.first(where: { $0.slug == slug }) {
            return ReaderResult(kind: .resource, title: r.title, pillar: r.pillar, bodyMd: readerBody, locked: false, lockReason: nil, supplement: r.supplement, track: nil, pair: nil)
        }
        return nil
    }
}
