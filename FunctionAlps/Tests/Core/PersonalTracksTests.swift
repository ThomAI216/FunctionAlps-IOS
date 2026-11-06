import Foundation
import Testing
@testable import FunctionAlps

/// Personal mini tracks (CLINICAL migration 283): grouping, order, the two kinds of item, what counts as opened,
/// the card under the message, and the deep link.
@Suite("Personal tracks")
struct PersonalTracksTests {
    private func track(_ id: String, _ title: String? = "T", at: TimeInterval = 0, message: String? = nil, intro: String? = nil) -> PersonalTrackRow {
        PersonalTrackRow(id: id, title: title, introMd: intro, createdAt: Date(timeIntervalSince1970: at), originMessageId: message)
    }
    private func lesson(_ track: String, _ pos: Int?, slug: String?, bank: String? = nil) -> PersonalTrackLessonRow {
        PersonalTrackLessonRow(patientTrackId: track, position: pos, contentSlug: slug, habitBankId: bank)
    }

    @Test func newestFirstItemsByPositionEachUnderItsTrack() {
        let out = PersonalTrackLogic.assemble(
            tracks: [track("a", "Older", at: 10), track("b", "Newer", at: 20)],
            lessons: [lesson("a", 2, slug: "sleep"), lesson("b", 1, slug: "x"), lesson("a", 1, slug: "light"), lesson("b", 2, slug: "y")])
        #expect(out.map(\.id) == ["b", "a"])
        #expect(out[1].items.compactMap(\.slug) == ["light", "sleep"])
        #expect(out[0].items.compactMap(\.slug) == ["x", "y"])
    }

    @Test func actionCardIsNeverAnArticle() {
        let out = PersonalTrackLogic.assemble(
            tracks: [track("a")],
            lessons: [lesson("a", 1, slug: "action:card-1", bank: "card-1"), lesson("a", 2, slug: "action:card-2"), lesson("a", 3, slug: "walk")])
        #expect(out[0].items.map(\.kind) == [.action("card-1"), .action("card-2"), .article("walk")])
        #expect(out[0].items.compactMap(\.slug) == ["walk"])
    }

    @Test func emptyRowsDuplicatesAndUntitledTracksAreDropped() {
        let out = PersonalTrackLogic.assemble(
            tracks: [track("a"), track("b", nil), track("c", "  ")],
            lessons: [lesson("a", 1, slug: ""), lesson("a", 2, slug: "walk"), lesson("a", 3, slug: "walk"), lesson("a", 4, slug: "action:")])
        #expect(out.map(\.id) == ["a"])
        #expect(out[0].items.count == 1)
    }

    @Test func openedIsCountedOnArticlesOnly() {
        let t = PersonalTrackLogic.assemble(tracks: [track("a")], lessons: [lesson("a", 1, slug: "sleep"), lesson("a", 2, slug: "light"), lesson("a", 3, slug: nil, bank: "c")])[0]
        #expect(PersonalTrackLogic.openedCount(t, openedSlugs: ["sleep", "other"]) == 1)
        #expect(PersonalTrackLogic.unopened(t, openedSlugs: ["sleep"]) == ["light"])
        #expect(t.items.count == 3)
    }

    @Test func unopenedCountDoesNotDoubleCountASlugAlreadyCounted() {
        let a = PersonalTrackLogic.assemble(tracks: [track("a")], lessons: [lesson("a", 1, slug: "sleep"), lesson("a", 2, slug: "light")])
        let b = PersonalTrackLogic.assemble(tracks: [track("b", at: 5)], lessons: [lesson("b", 1, slug: "light"), lesson("b", 2, slug: "walk")])
        #expect(PersonalTrackLogic.unopenedCount(a + b, openedSlugs: [], alreadyCounted: []) == 3)
        #expect(PersonalTrackLogic.unopenedCount(a + b, openedSlugs: ["walk"], alreadyCounted: ["sleep"]) == 1)
    }

    @Test func introPreviewIsOneParagraphAndShortened() throws {
        #expect(PersonalTrackLogic.introPreview("  \n ") == nil)
        #expect(PersonalTrackLogic.introPreview("Hello Marie.\n\nTwo things.") == "Hello Marie. Two things.")
        let long = String(repeating: "word ", count: 60)
        let preview = try #require(PersonalTrackLogic.introPreview(long, limit: 20))
        #expect(preview.hasSuffix("…"))
        #expect(preview.count <= 21)
    }

    @Test func countLabelIsNeverOneResources() {
        #expect(PersonalTrackLogic.countLabel(1) == "1 resource")
        #expect(PersonalTrackLogic.countLabel(3) == "3 resources")
    }

    @Test func messageCarriesItsTrackAndDropsDuplicateResources() throws {
        let t = PersonalTrackLogic.assemble(tracks: [track("t1", "Afternoon energy", message: "m2")], lessons: [lesson("t1", 1, slug: "sleep"), lesson("t1", 2, slug: "action:c")])
        func msg(_ id: String, mine: Bool = false) -> PatientMessage {
            PatientMessage(id: id, mine: mine, text: "hi", createdAt: Date(timeIntervalSince1970: 0), unread: false, context: nil)
        }
        func res(_ id: String, _ message: String, _ slug: String) -> MessageResource {
            MessageResource(id: id, messageId: message, slug: slug, title: slug, kind: .resource, createdAt: Date(timeIntervalSince1970: 0), openedAt: nil)
        }
        let resources = [res("r1", "m2", "sleep"), res("r2", "m2", "walk"), res("r3", "m1", "sleep")]
        let thread = MessagingLogic.attach(tracks: t, to: MessagingLogic.attach(resources, to: [msg("m1"), msg("m2"), msg("m3", mine: true)]))
        #expect(thread[0].track == nil)
        #expect(thread[0].resources.map(\.id) == ["r3"])
        #expect(thread[1].track == PersonalTrackSummary(id: "t1", title: "Afternoon energy", itemCount: 2, actionFlags: [false, true]))
        #expect(thread[1].resources.map(\.id) == ["r2"])
        #expect(thread[2].track == nil)
        #expect(PersonalTrackLogic.messageLabel(try #require(thread[1].track)) == "Afternoon energy · 2 resources")
        // The Library's loose row keeps only what no track holds.
        #expect(PersonalTrackLogic.looseResources(resources, tracks: t).map(\.id) == ["r2", "r3"])
    }

    @Test func rowsDecodeFromTheWire() throws {
        let tracks = """
        [{"id":"t1","title":"Mine","intro_md":"Line one\\nLine two","created_at":"2026-11-05T09:00:00Z","origin_message_id":null}]
        """
        let lessons = """
        [{"patient_track_id":"t1","position":1,"content_slug":"action:c1","habit_bank_id":"c1"}]
        """
        let t = try JSON.decode([PersonalTrackRow].self, from: Data(tracks.utf8))
        let l = try JSON.decode([PersonalTrackLessonRow].self, from: Data(lessons.utf8))
        let out = PersonalTrackLogic.assemble(tracks: t, lessons: l)
        #expect(out[0].intro == "Line one\nLine two")
        #expect(out[0].items.map(\.kind) == [.action("c1")])
    }
}

@MainActor
@Suite("Deep link · library/track")
struct PersonalTrackLinkTests {
    private let id = "5a0c0000-0000-4000-8000-0000000000a1"

    @Test func trackLinkOpensTheTrackInTheLibrary() {
        let router = AppRouter()
        router.open(URL(string: "functionalps://library/track/\(id)")!)
        #expect(router.tab == .library)
        #expect(router.libraryPath == [.personalTrack(id)])
    }

    @Test func upperCaseIdIsNormalised() {
        let router = AppRouter()
        router.open(URL(string: "functionalps://library/track/\(id.uppercased())")!)
        #expect(router.libraryPath == [.personalTrack(id)])
    }

    @Test func malformedOrMissingIdLandsOnTheLibrary() {
        let router = AppRouter()
        router.open(URL(string: "functionalps://library/track/not-a-uuid")!)
        #expect(router.tab == .library && router.libraryPath.isEmpty)
        router.open(URL(string: "functionalps://library/track")!)
        #expect(router.libraryPath.isEmpty)
    }

    @Test func theOtherLibraryLinksStillWork() {
        let router = AppRouter()
        router.open(URL(string: "functionalps://library/sent")!)
        #expect(router.libraryPath == [.sentTrack])
        router.open(URL(string: "functionalps://library/sleep-basics")!)
        #expect(router.libraryPath == [.read("sleep-basics")])
        router.open(URL(string: "functionalps://library")!)
        #expect(router.libraryPath.isEmpty)
    }
}

@Suite("Personal track · the path")
struct PersonalTrackPathTests {
    private func track(_ items: [PersonalTrackItem]) -> PersonalTrack {
        PersonalTrack(id: "t", title: "T", intro: "", createdAt: Date(timeIntervalSince1970: 0), originMessageId: nil, items: items)
    }
    private let a = PersonalTrackItem(position: 1, kind: .article("a"))
    private let b = PersonalTrackItem(position: 2, kind: .article("b"))
    private let c = PersonalTrackItem(position: 3, kind: .action("card"))

    private func states(_ steps: [PersonalTrackStep]) -> [PersonalTrackStepState] { steps.map(\.state) }

    @Test func nothingDoneFirstIsCurrentCheckInWaits() {
        let steps = PersonalTrackLogic.steps(track([a, b, c]), openedSlugs: [], planCardIds: [])
        #expect(states(steps) == [.current, .upcoming, .upcoming, .upcoming])
        #expect(steps.map(\.number) == [1, 2, 3, 4])
        #expect(steps.last?.kind == .checkIn)
    }

    @Test func doneStepsAreArticlesOpenedAndActionsInThePlan() {
        let steps = PersonalTrackLogic.steps(track([a, b, c]), openedSlugs: ["a"], planCardIds: ["card"])
        #expect(states(steps) == [.done, .current, .done, .upcoming])
    }

    @Test func currentIsTheFirstNotDoneEvenWhenALaterOneIsDone() {
        let steps = PersonalTrackLogic.steps(track([a, b, c]), openedSlugs: ["b"], planCardIds: [])
        #expect(states(steps) == [.current, .done, .upcoming, .upcoming])
    }

    @Test func checkInIsCurrentOnlyWhenEveryItemIsDone() {
        let steps = PersonalTrackLogic.steps(track([a, b, c]), openedSlugs: ["a", "b"], planCardIds: ["card"])
        #expect(states(steps) == [.done, .done, .done, .current])
    }

    @Test func itemsFollowPositionNotArrayOrder() {
        let steps = PersonalTrackLogic.steps(track([c, a, b]), openedSlugs: [], planCardIds: [])
        #expect(steps.compactMap { if case .item(let i) = $0.kind { i.id } else { nil } } == [a.id, b.id, c.id])
    }

    @Test func noItemsNoPath() {
        #expect(PersonalTrackLogic.steps(track([]), openedSlugs: [], planCardIds: []).isEmpty)
    }

    @Test func putOffActionLetsTheNextStepLead() {
        let act = PersonalTrackItem(position: 1, kind: .action("card"))
        let t = track([act, PersonalTrackItem(position: 2, kind: .article("a")), PersonalTrackItem(position: 3, kind: .article("b"))])
        let plain = PersonalTrackLogic.steps(t, openedSlugs: [], planCardIds: [])
        #expect(states(plain) == [.current, .upcoming, .upcoming, .upcoming])
        let later = PersonalTrackLogic.steps(t, openedSlugs: [], planCardIds: [], deferred: [act.id])
        #expect(states(later) == [.upcoming, .current, .upcoming, .upcoming])
        #expect(PersonalTrackLogic.canPutOff(plain[0], in: plain, deferred: []))
        #expect(!PersonalTrackLogic.canPutOff(plain[1], in: plain, deferred: []))
    }

    @Test func putOffIsNotOfferedWhenNothingElseIsOpen() {
        let t = track([c])
        let steps = PersonalTrackLogic.steps(t, openedSlugs: [], planCardIds: [])
        #expect(!PersonalTrackLogic.canPutOff(steps[0], in: steps, deferred: []))
        // Everything left put off: the first of them is still current, the check-in does not jump ahead.
        let later = PersonalTrackLogic.steps(t, openedSlugs: [], planCardIds: [], deferred: ["action:card"])
        #expect(states(later) == [.current, .upcoming])
    }

    @Test func progressCountsItemsOnlyNotTheCheckIn() {
        let p = PersonalTrackLogic.progress(track([a, b, c]), openedSlugs: ["a"], planCardIds: ["card"])
        #expect(p.done == 2 && p.total == 3)
        #expect(PersonalTrackLogic.progressFraction(done: 2, total: 3) > 0.66)
        #expect(PersonalTrackLogic.progressFraction(done: 0, total: 0) == 0)
        #expect(PersonalTrackLogic.progressFraction(done: 5, total: 3) == 1)
    }

    @Test func heroEyebrowIsTheEyebrowAndTheSentDay() {
        let en = Locale(identifier: "en_GB")
        let utc = TimeZone(identifier: "UTC")!
        let sent = Date(timeIntervalSince1970: 1_793_836_800) // 2026-11-05 00:00 UTC
        #expect(PersonalTrackLogic.heroEyebrow(sentAt: sent, locale: en, timeZone: utc) == "Curated for you · 5 Nov")
        // The member's day, not UTC: 23:30 UTC on the 4th is already the 5th in Zurich.
        let late = Date(timeIntervalSince1970: 1_793_836_800 - 1800)
        #expect(PersonalTrackLogic.heroEyebrow(sentAt: late, locale: en, timeZone: TimeZone(identifier: "Europe/Zurich")!) == "Curated for you · 5 Nov")
    }

    @Test func initialsFromTheName() {
        #expect(PersonalTrackLogic.initials("Anna Keller") == "AK")
        #expect(PersonalTrackLogic.initials("  anna ") == "A")
        #expect(PersonalTrackLogic.initials("Anna Maria Keller") == "AM")
        #expect(PersonalTrackLogic.initials(nil) == nil)
        #expect(PersonalTrackLogic.initials("   ") == nil)
    }

    @Test func picksLabelNeverSaysOnePicks() {
        #expect(PersonalTrackLogic.picksLabel(1) == "1 pick")
        #expect(PersonalTrackLogic.picksLabel(3) == "3 picks")
    }
}
