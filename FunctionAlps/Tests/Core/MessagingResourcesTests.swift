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
