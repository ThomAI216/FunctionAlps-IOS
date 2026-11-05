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
        #expect(thread[1].track == PersonalTrackSummary(id: "t1", title: "Afternoon energy", itemCount: 2))
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
