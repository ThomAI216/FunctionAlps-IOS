import Foundation
import Testing
@testable import FunctionAlps

@Suite("Library rules (one rulebook with the members dashboard)")
struct LibraryLogicTests {
    private func lesson(_ slug: String, done: Bool) -> TrackLesson {
        TrackLesson(contentSlug: slug, position: 1, title: slug, locked: false, done: done, publishedAt: nil, coverURL: nil)
    }

    @Test func progressAndState() {
        #expect(LibraryLogic.trackPct(done: 2, total: 6) == 33)
        #expect(LibraryLogic.trackPct(done: 0, total: 0) == 0)
        #expect(LibraryLogic.trackState(unlocked: false, done: 3, total: 3) == .locked)
        #expect(LibraryLogic.trackState(unlocked: true, done: 3, total: 3) == .completed)
        #expect(LibraryLogic.trackState(unlocked: true, done: 1, total: 3) == .inProgress)
        #expect(LibraryLogic.trackState(unlocked: true, done: 0, total: 3) == .new)
    }

    @Test func sequentialAccessIsOpenWhileTheGateIsOff() {
        let lessons = [lesson("a", done: true), lesson("b", done: false), lesson("c", done: false)]
        let first = LibraryLogic.firstOpenIndex(lessons)
        #expect(first == 1)
        #expect(LibraryLogic.lessonAccess(index: 0, first: first) == .done)
        #expect(LibraryLogic.lessonAccess(index: 1, first: first) == .current)
        #expect(LibraryLogic.lessonAccess(index: 2, first: first) == .open)
        #expect(LibraryLogic.firstOpenIndex([lesson("a", done: true)]) == 1)
    }

    @Test func gates() {
        #expect(LibraryLogic.isStageSatisfied(required: nil, stage: .lead))
        #expect(LibraryLogic.isStageSatisfied(required: "active", stage: .alumni))
        #expect(!LibraryLogic.isStageSatisfied(required: "active", stage: .lead))
        let gate = LibraryLogic.TrackGate(requiresStage: nil, requiresTrackSlug: "gut")
        #expect(LibraryLogic.isTrackUnlocked(gate, stage: .lead, doneBySlug: ["gut": 3], totalBySlug: ["gut": 3]))
        #expect(!LibraryLogic.isTrackUnlocked(gate, stage: .lead, doneBySlug: ["gut": 2], totalBySlug: ["gut": 3]))
        // "nothing to finish is not finished"
        #expect(!LibraryLogic.isTrackUnlocked(gate, stage: .lead, doneBySlug: [:], totalBySlug: ["gut": 0]))
        #expect(!LibraryLogic.isTrackUnlocked(gate, stage: .lead, doneBySlug: [:], totalBySlug: [:]))
    }

    @Test func assembleBuildsTracksResourcesAndFailsAccessClosed() throws {
        var raw = LibraryRaw()
        raw.tracks = [
            LibraryRawTrack(id: "t1", slug: "gut-reset", title: "Gut Reset", description: "d", pillar: "intestin", coverStyle: nil, position: 1, requiresStage: nil, requiresTrackId: nil),
            LibraryRawTrack(id: "t2", slug: "energy-reset", title: "Energy", description: nil, pillar: "energie", coverStyle: nil, position: 2, requiresStage: "active", requiresTrackId: nil),
        ]
        raw.lessons = [LibraryRawLesson(trackId: "t1", position: 2, contentSlug: "calm"), LibraryRawLesson(trackId: "t1", position: 1, contentSlug: "understand")]
        raw.progress = [LibraryRawProgress(trackId: "t1", contentSlug: "understand"), LibraryRawProgress(trackId: nil, contentSlug: "walking")]
        raw.list = [
            LibraryListRow(slug: "understand", title: "Understand your gut", summary: nil, publishedAt: "2026-08-01", tags: ["pillar:intestin"], isLocked: false, coverUrl: "https://x/cover.png"),
            LibraryListRow(slug: "walking", title: "Post-meal walking", summary: "s", publishedAt: nil, tags: ["pillar:intestin", "supplement"], isLocked: true, coverUrl: "javascript:alert(1)"),
        ]
        raw.priorityTrackIds = ["t2", "nope"]
        let b = try #require(LibraryLogic.assemble(raw, stage: .lead))
        #expect(b.access == .none)
        #expect(b.tracks[0].lessons.map(\.contentSlug) == ["understand", "calm"])
        #expect(b.tracks[0].done == 1 && b.tracks[0].total == 2 && b.tracks[0].state == .inProgress)
        #expect(b.tracks[0].lessons[0].coverURL?.absoluteString == "https://x/cover.png")
        #expect(b.tracks[0].lessons[1].title == "Calm")
        #expect(b.tracks[1].state == .locked && b.tracks[1].lockLabel != nil)
        #expect(b.resources.map(\.slug) == ["walking"])
        #expect(b.resources[0].supplement && b.resources[0].locked && b.resources[0].coverURL == nil)
        #expect(b.prioritySlugs == ["energy-reset"])
        #expect(LibraryLogic.assemble(LibraryRaw(), stage: .active) == nil)
    }

    @Test func collapseAndThumbnailsAndWeeks() {
        #expect(LibraryLogic.visibleItems([1, 2, 3, 4, 5], expanded: false) == [1, 2, 3, 4])
        #expect(LibraryLogic.visibleItems([1, 2, 3, 4], expanded: false) == [1, 2, 3, 4])
        #expect(LibraryLogic.toggleLabel(total: 4, expanded: false, noun: "tracks") == nil)
        #expect(LibraryLogic.toggleLabel(total: 9, expanded: false, noun: "tracks") != nil)
        let thumb = LibraryLogic.storageThumbnail(URL(string: "https://p.supabase.co/storage/v1/object/public/content-public/a.png?x=1"), width: 512, height: 512)
        #expect(thumb?.absoluteString == "https://p.supabase.co/storage/v1/render/image/public/content-public/a.png?width=512&height=512&resize=contain&quality=70")
        #expect(LibraryLogic.storageThumbnail(URL(string: "https://cdn.example/a.png"), width: 1, height: 1)?.absoluteString == "https://cdn.example/a.png")
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        #expect(LibraryLogic.weekNumber(startDate: "2026-08-20", now: now) == 3)
        #expect(LibraryLogic.weekNumber(startDate: "2026-09-10", now: now) == nil)
        #expect(LibraryLogic.weekNumber(startDate: nil, now: now) == nil)
    }

    @Test func markdownCoversTheCorpus() {
        let blocks = LibraryMarkdown.parse("# Title\n\nSome **bold** and *italic* text\ncontinues here.\n\n- one\n- two\n\n1. first\n2) second\n\n![Alt text](https://x/img.png)\n")
        #expect(blocks.count == 5)
        if case .heading(let level, let runs) = blocks[0] { #expect(level == 1 && runs == [LibraryMarkdown.Run(text: "Title")]) } else { Issue.record("heading") }
        if case .paragraph(let runs) = blocks[1] {
            #expect(runs.count == 5 && runs[1].bold && runs[3].italic && runs[4].text == " text continues here.")
        } else { Issue.record("paragraph") }
        if case .bullets(let items) = blocks[2] { #expect(items.count == 2) } else { Issue.record("bullets") }
        if case .numbered(let items) = blocks[3] { #expect(items.count == 2) } else { Issue.record("numbered") }
        if case .image(let src, let alt) = blocks[4] { #expect(src == "https://x/img.png" && alt == "Alt text") } else { Issue.record("image") }
    }

    @Test func readerResolvesLessonsAndLocks() throws {
        let bundle = LibraryDemo.bundle
        let row = LibraryGetRow(title: "Calm the fire", tags: ["pair:demo-gut-reset-1"], bodyMd: "body", locked: false)
        let r = try #require(LibraryLogic.reader(slug: "demo-gut-reset-2", bundle: bundle, row: row))
        #expect(r.kind == .lesson && r.track?.index == 1 && r.track?.total == 6 && r.bodyMd == "body")
        #expect(r.pair?.title == "Understand your gut")
        let locked = LibraryGetRow(title: "X", tags: [], bodyMd: nil, locked: true)
        let res = try #require(LibraryLogic.reader(slug: "unknown", bundle: bundle, row: locked))
        #expect(res.kind == .resource && res.locked && res.lockReason == .programme)
        #expect(LibraryLogic.reader(slug: "unknown", bundle: bundle, row: nil) == nil)
        #expect(LibraryLogic.completionCheck(bundle: bundle, trackSlug: "demo-gut-reset", contentSlug: "demo-gut-reset-1") == .ok)
        #expect(LibraryLogic.completionCheck(bundle: bundle, trackSlug: "demo-gut-reset", contentSlug: "demo-gut-reset-3") == nil)
        #expect(LibraryLogic.completionCheck(bundle: bundle, trackSlug: "demo-gut-reset", contentSlug: "demo-gut-reset-4") == .notCurrent)
    }
}

@Suite("Meal tips and flags")
struct MealTipsTests {
    @Test func dayParts() {
        #expect(MealTip.DayPart.current(hour: 7) == .morning)
        #expect(MealTip.DayPart.current(hour: 13) == .afternoon)
        #expect(MealTip.DayPart.current(hour: 19) == .evening)
        #expect(MealTip.DayPart.current(hour: 23) == .night)
        #expect(MealTip.DayPart.current(hour: 3) == .night)
    }

    @Test func selectionKeepsTheDayPartAndUniversals() {
        let tips = MealTips.select(dayPart: .evening)
        #expect(!tips.isEmpty)
        #expect(tips.allSatisfy { $0.dayParts.isEmpty || $0.dayParts.contains(.evening) })
        #expect(tips.first?.dayParts.contains(.evening) == true)
        #expect(MealTips.all.count == 32)
    }

    @Test func flagsFollowTheRegistryOrderAndDropUnknowns() {
        let item = MealItem(name: "salmon", flags: ["omega3", "weird", "protein"])
        #expect(FoodFlag.flags(of: item) == [.protein, .omega3])
        #expect(FoodFlag.flags(in: [item, MealItem(name: "bread", flags: ["fastSugars"])]) == [.protein, .omega3, .fastSugars])
    }
}
