import Foundation
import Testing
@testable import FunctionAlps

@Suite("Library topic covers — the members web's covers.ts rules")
struct TopicCoverTests {
    private let base = "https://ndojytvvlvlbgtodujkf.supabase.co/storage/v1/object/public/content-public/library/covers/"
    private func url(_ name: String) -> URL { URL(string: base + name + ".webp")! }
    private var covers: [String: URL] {
        ["foundations": url("foundations"), "intestin": url("intestin"), "energie": url("energie"),
         "sommeil": url("sommeil"), "mouvement": url("mouvement"), "stress": url("stress")]
    }

    @Test func topicKeyTrimsLowercasesAndAliases() {
        #expect(LibraryLogic.topicKey("gut") == "intestin")
        #expect(LibraryLogic.topicKey("Energy") == "energie")
        #expect(LibraryLogic.topicKey(" sleep ") == "sommeil")
        #expect(LibraryLogic.topicKey("MOVEMENT") == "mouvement")
        #expect(LibraryLogic.topicKey("Stress") == "stress")
        #expect(LibraryLogic.topicKey("intestin") == "intestin")
        #expect(LibraryLogic.topicKey("") == "foundations")
        #expect(LibraryLogic.topicKey("   ") == "foundations")
        #expect(LibraryLogic.topicKey(nil) == "foundations")
    }

    @Test func resourceTopicIsTheFirstPillarTag() {
        #expect(LibraryLogic.topicKey(fromTags: ["recipe", "sommeil", "intestin"]) == "sommeil")
        #expect(LibraryLogic.topicKey(fromTags: ["supplement", "pair:magnesium"]) == "foundations")
        #expect(LibraryLogic.topicKey(fromTags: ["pillar:intestin"]) == "foundations")   // the web matches bare keys only
        #expect(LibraryLogic.topicKey(fromTags: []) == "foundations")
        #expect(LibraryLogic.topicKey(fromTags: nil) == "foundations")
    }

    @Test func firstHitWins() {
        let explicit = url("patient-track"), own = url("track-own")
        #expect(LibraryLogic.resolveCover(explicit: explicit, own: own, pillar: "gut", covers: covers) == explicit)
        #expect(LibraryLogic.resolveCover(explicit: nil, own: own, pillar: "gut", covers: covers) == own)
        #expect(LibraryLogic.resolveCover(explicit: nil, own: nil, pillar: "gut", covers: covers) == url("intestin"))
        // A topic without its own cover falls back to foundations.
        #expect(LibraryLogic.resolveCover(explicit: nil, own: nil, pillar: "hormones", covers: covers) == url("foundations"))
        #expect(LibraryLogic.resolveCover(explicit: nil, own: nil, pillar: nil, covers: covers) == url("foundations"))
    }

    @Test func emptyMapLeavesTheGradient() {
        #expect(LibraryLogic.resolveCover(explicit: nil, own: nil, pillar: "sleep", covers: [:]) == nil)
        #expect(LibraryLogic.resolveCover(explicit: nil, own: url("own"), pillar: "sleep", covers: [:]) == url("own"))
    }

    @Test func rowsWithoutAnHttpURLAreSkipped() {
        let map = LibraryLogic.topicCovers([
            LibraryTopicCoverRow(topic: "energie", imageUrl: base + "energie-20260930T100753Z.webp"),
            LibraryTopicCoverRow(topic: "sommeil", imageUrl: ""),
            LibraryTopicCoverRow(topic: "stress", imageUrl: nil),
            LibraryTopicCoverRow(topic: "intestin", imageUrl: "javascript:alert(1)"),
        ])
        #expect(map.keys.sorted() == ["energie"])
    }

    @Test func assemblyResolvesTrackAndResourceCovers() throws {
        var raw = LibraryRaw()
        raw.tracks = [
            LibraryRawTrack(id: "t1", slug: "gut-reset", title: "Gut Reset", description: nil, pillar: "Gut", coverStyle: nil, position: 1, requiresStage: nil, requiresTrackId: nil),
            LibraryRawTrack(id: "t2", slug: "own-art", title: "Own", description: nil, pillar: "energie", coverStyle: nil, position: 2, requiresStage: nil, requiresTrackId: nil,
                            coverImageUrl: base + "own.webp"),
            LibraryRawTrack(id: "t3", slug: "no-pillar", title: "None", description: nil, pillar: nil, coverStyle: nil, position: 3, requiresStage: nil, requiresTrackId: nil),
        ]
        raw.list = [LibraryListRow(slug: "nsdr", title: "NSDR", summary: nil, publishedAt: nil, tags: ["sommeil"], isLocked: false, coverUrl: nil)]
        let bundle = try #require(LibraryLogic.assemble(raw, stage: .active, covers: covers))
        #expect(bundle.tracks.map(\.cover) == [url("intestin"), url("own"), url("foundations")])
        #expect(bundle.resources.first?.cover == url("sommeil"))

        let bare = try #require(LibraryLogic.assemble(raw, stage: .active))
        #expect(bare.tracks.map(\.cover) == [nil, url("own"), nil])
        #expect(bare.resources.first?.cover == nil)
    }
}
