import Foundation
import Testing
@testable import FunctionAlps

/// Resources sent with a message (CLINICAL migration 277): each card goes under its own bubble, in the
/// order it was sent; the Library row shows one card per item, the latest send first.
@Suite("Messaging · resources sent with a message")
struct MessagingResourcesTests {
    private func message(_ id: String, mine: Bool = false, at: TimeInterval = 0) -> PatientMessage {
        PatientMessage(id: id, mine: mine, text: "hello", createdAt: Date(timeIntervalSince1970: at), unread: false, context: nil)
    }

    private func resource(_ id: String, message: String, slug: String, at: TimeInterval, opened: Bool = false) -> MessageResource {
        MessageResource(id: id, messageId: message, slug: slug, title: slug, kind: .resource,
                        createdAt: Date(timeIntervalSince1970: at), openedAt: opened ? Date(timeIntervalSince1970: at + 10) : nil)
    }

    @Test func eachCardUnderItsOwnBubbleInSendOrder() {
        let thread = [message("m1"), message("m2", mine: true), message("m3")]
        let sent = [
            resource("r2", message: "m3", slug: "sleep", at: 20),
            resource("r1", message: "m3", slug: "light", at: 10),
            resource("r9", message: "gone", slug: "orphan", at: 5),
        ]
        let out = MessagingLogic.attach(sent, to: thread)
        #expect(out.map(\.resources.count) == [0, 0, 2])
        #expect(out[2].resources.map(\.slug) == ["light", "sleep"])
        // The member's own message never carries a card; an orphan card is dropped, not misplaced.
        #expect(out.flatMap(\.resources).map(\.id).contains("r9") == false)
    }

    @Test func libraryRowIsNewestFirstOnePerItem() {
        let sent = [
            resource("a", message: "m1", slug: "sleep", at: 10, opened: true),
            resource("b", message: "m2", slug: "sleep", at: 30),
            resource("c", message: "m2", slug: "light", at: 20),
        ]
        let row = MessagingLogic.sentForLibrary(sent)
        #expect(row.map(\.id) == ["b", "c"])
        #expect(row[0].openedAt == nil)
    }

    @Test func rowDecodesTheMemberReadableColumns() throws {
        let json = """
        [{"id":"r1","message_id":"m1","library_slug":"sleep-basics","title":"Sleep basics","kind":"action","created_at":"2026-11-05T09:00:00Z","opened_at":null}]
        """
        let rows = try JSON.decode([MessageResourceRow].self, from: Data(json.utf8))
        let r = try #require(rows.first).resource
        #expect(r.slug == "sleep-basics")
        #expect(r.kind == .action)
        #expect(r.openedAt == nil)
        #expect(r.messageId == "m1")
    }

    @Test func unknownKindReadsAsResource() throws {
        let json = """
        [{"id":"r1","message_id":"m1","library_slug":"x","title":"X","kind":"video","created_at":"2026-11-05T09:00:00Z","opened_at":"2026-11-05T10:00:00Z"}]
        """
        let r = try #require(try JSON.decode([MessageResourceRow].self, from: Data(json.utf8)).first).resource
        #expect(r.kind == .resource)
        #expect(r.openedAt != nil)
    }
}

extension MessagingResourcesTests {
    @Test func badgeCountsUnopenedItemsOncePerSlug() {
        let sent = [
            resource("a", message: "m1", slug: "sleep", at: 10),
            resource("b", message: "m2", slug: "sleep", at: 30),
            resource("c", message: "m2", slug: "light", at: 20, opened: true),
            resource("d", message: "m3", slug: "walk", at: 40),
        ]
        #expect(MessagingLogic.unopenedCount(sent) == 2)
        #expect(MessagingLogic.unopenedCount([]) == 0)
    }
}

/// "Your Pathway" — what the sentence under the title rests on (owner, 2026-11-05). Same rules as CLINICAL's
/// `lib/conversations/pathway.ts`, so the practitioner's preview and the phone say the same thing.
@Suite("Pathway intro")
struct PathwayIntroTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func d(_ s: String) -> Date { ISO8601.parse(s)! }

    @Test func consultationAndTheLastThreeConversationDaysOldestFirst() {
        let sent = ["2026-11-01T09:00:00Z", "2026-11-04T16:00:00Z", "2026-11-04T16:30:00Z", "2026-10-20T08:00:00Z", "2026-11-03T12:00:00Z"].map(d)
        let intro = PathwayLogic.intro(consultation: d("2026-10-12T10:00:00Z"), sentAt: sent, objective: "  Get your energy back  ", calendar: utc)
        guard case let .consultationAndConversations(c, days) = intro.basis else { Issue.record("wrong basis \(intro.basis)"); return }
        #expect(c == d("2026-10-12T10:00:00Z"))
        // Same day counted once; the oldest (20 Oct) drops out of the three most recent.
        #expect(days == ["2026-11-01T00:00:00Z", "2026-11-03T00:00:00Z", "2026-11-04T00:00:00Z"].map(d))
        #expect(intro.focus == "Get your energy back")
    }

    @Test func eachPartDropsOutOnItsOwn() {
        #expect(PathwayLogic.intro(consultation: nil, sentAt: [d("2026-11-04T16:00:00Z")], objective: nil, calendar: utc).basis
                == .conversations([d("2026-11-04T00:00:00Z")]))
        #expect(PathwayLogic.intro(consultation: d("2026-10-12T10:00:00Z"), sentAt: [], objective: "x", calendar: utc).basis
                == .consultation(d("2026-10-12T10:00:00Z")))
        let empty = PathwayLogic.intro(consultation: nil, sentAt: [], objective: "   ", calendar: utc)
        #expect(empty.basis == .none)
        #expect(empty.focus == nil)
        #expect(PathwayLogic.sentence(.none) == nil)
    }
}
