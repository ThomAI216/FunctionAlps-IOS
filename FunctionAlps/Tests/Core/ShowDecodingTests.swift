import Foundation
import Testing
@testable import FunctionAlps

@Suite("The show: tolerant decoding of the CLINICAL library API (old shape, new shape, garbage)")
struct ShowDecodingTests {
    private func list(_ json: String) -> ShowLibrary? { ShowLibrary.decodeList(Data(json.utf8)) }
    private func episode(_ json: String) -> ShowEpisode? { ShowEpisode.decode(Data(json.utf8)) }

    @Test func newShape() throws {
        let lib = try #require(list(#"""
        {
          "ok": true,
          "series": {
            "slug": "the-functionalps-show", "name": "The FunctionAlps Show",
            "description": { "en": "Daily", "fr": null }, "image_url": "https://cdn.example.com/s.png",
            "feed_url": "https://example.com/feed.xml", "video_feed_url": "",
            "schedule": [
              { "weekday": 6, "kind": "live", "track": "cross", "minutes": 45 },
              { "weekday": 1, "live": true, "track": "cross", "minutes": 45 },
              { "weekday": 2, "kind": "episode", "track": "movement", "minutes": 30 }
            ],
            "time": "12:30", "timezone": "Europe/Zurich"
          },
          "episodes": [
            { "slug": "ep-1", "kind": "episode", "number": 1, "title": { "en": "One", "fr": "Un" }, "summary": { "en": "s" },
              "track": "movement", "level": 1, "starts_at": "2026-10-06T10:30:00.000Z", "published_at": "2026-10-06T14:00:00Z",
              "duration_seconds": 1805.4, "audio_url": "https://cdn.example.com/1.mp3",
              "has": { "research": true, "article": true, "guide": true, "faq": true, "show_notes": true, "video": false } },
            { "slug": "ep-2", "kind": "live", "number": 2.0, "title": { "en": "Two" }, "track": "cross",
              "starts_at": "2026-10-10T10:30:00+00:00", "duration_seconds": null, "audio_url": null, "has": {} }
          ],
          "upcoming": [
            { "slug": "live-17", "kind": "live", "number": null, "title": { "en": "Later" }, "track": "cross",
              "starts_at": "2026-10-17T10:30:00Z", "ends_at": "2026-10-17T11:15:00Z" },
            { "slug": "ep-13", "kind": "episode", "number": 5, "title": { "fr": "Seulement français" }, "track": "movement",
              "starts_at": "2026-10-13T10:30:00Z", "ends_at": "garbage" }
          ]
        }
        """#))
        #expect(lib.series?.name == "The FunctionAlps Show")
        #expect(lib.clock.schedule.map(\.weekday) == [1, 2, 6])
        #expect(lib.clock.schedule.first?.kind == .live)
        #expect(lib.clock.time == "12:30")
        #expect(lib.episodes.map(\.slug) == ["ep-2", "ep-1"])
        let one = try #require(lib.episodes.last)
        #expect(one.durationSeconds == 1805)
        #expect(one.audioURL?.absoluteString == "https://cdn.example.com/1.mp3")
        #expect(one.has.showNotes && one.has.guide && !one.has.video)
        #expect(one.title.pick("fr") == "Un")
        #expect(lib.episodes.first?.kind == .live)
        #expect(lib.episodes.first?.number == 2)
        #expect(lib.upcoming.map(\.slug) == ["ep-13", "live-17"])
        let frOnly = try #require(lib.upcoming.first)
        #expect(frOnly.title.pick("en") == "Seulement français")
        #expect(frOnly.endsAt == frOnly.startsAt.addingTimeInterval(45 * 60))
    }

    @Test func oldShapeGetsTheDefaults() throws {
        let lib = try #require(list(#"""
        {
          "ok": true,
          "series": { "slug": "the-functionalps-show", "name": "The FunctionAlps Show", "description": { "en": null, "fr": null },
                      "image_url": null, "feed_url": "https://example.com/feed.xml", "video_feed_url": "https://example.com/v.xml" },
          "episodes": [
            { "slug": "ep-1", "number": 1, "title": { "en": "One", "fr": null }, "summary": { "en": null, "fr": null },
              "track": "movement", "level": null, "starts_at": "2026-10-06T10:30:00Z", "published_at": null,
              "duration_seconds": 1800, "audio_url": null,
              "has": { "research": false, "article": false, "guide": false, "faq": false, "show_notes": false, "video": false } }
          ]
        }
        """#))
        #expect(lib.upcoming.isEmpty)
        #expect(lib.episodes.first?.kind == .episode)
        #expect(lib.clock == .standard)
        #expect(lib.clock.schedule == ShowLogic.defaultSchedule)
        #expect(lib.clock.time == "12:30")
        #expect(lib.clock.timezone == "Europe/Zurich")
    }

    @Test func noSeriesAndNoEpisodesYetIsStillShowData() throws {
        let lib = try #require(list(#"{ "ok": true, "series": null, "episodes": [] }"#))
        #expect(lib.series == nil)
        #expect(lib.episodes.isEmpty)
        #expect(lib.clock == .standard)
    }

    @Test func garbageIsNoShowData() {
        #expect(list(#"{ "ok": false, "error": "boom" }"#) == nil)
        #expect(list(#"{ "ok": true }"#) == nil)
        #expect(list(#"{ "ok": true, "episodes": "nope" }"#) == nil)
        #expect(list(#"{ "ok": "true", "episodes": [] }"#) == nil)
        #expect(list(#"[]"#) == nil)
        #expect(list("<html>502</html>") == nil)
        #expect(list("") == nil)
    }

    @Test func malformedItemsAreDroppedOneByOne() throws {
        let lib = try #require(list(#"""
        {
          "ok": true,
          "series": "not an object",
          "episodes": [
            { "slug": "good", "title": { "en": "Good" }, "starts_at": "2026-10-06T10:30:00Z", "track": "astrology", "number": "3", "level": 9 },
            { "slug": "Bad Slug", "title": { "en": "x" }, "starts_at": "2026-10-06T10:30:00Z" },
            { "slug": "no-title", "title": { "en": "  " }, "starts_at": "2026-10-06T10:30:00Z" },
            { "slug": "no-date", "title": { "en": "x" }, "starts_at": "tomorrow" },
            42, null, "string"
          ],
          "upcoming": { "not": "an array" }
        }
        """#))
        #expect(lib.series == nil)
        #expect(lib.clock == .standard)
        #expect(lib.episodes.map(\.slug) == ["good"])
        let good = try #require(lib.episodes.first)
        #expect(good.track == nil)
        #expect(good.number == nil)
        #expect(good.level == nil)
        #expect(good.audioURL == nil)
        #expect(good.has == ShowEpisodeHas())
        #expect(lib.upcoming.isEmpty)
    }

    @Test func aBadScheduleFallsBackToTheDefaultWeek() throws {
        let lib = try #require(list(#"""
        { "ok": true, "episodes": [],
          "series": { "slug": "s", "name": "S", "schedule": [ { "weekday": 9, "track": "cross", "minutes": 45 }, { "weekday": 1, "track": "nope", "minutes": 45 } ],
                      "time": "25:99", "timezone": "Nowhere/Land" } }
        """#))
        #expect(lib.clock.schedule == ShowLogic.defaultSchedule)
        #expect(lib.clock.time == "12:30")
        #expect(lib.clock.timezone == "Europe/Zurich")
    }

    @Test func fullEpisode() throws {
        let ep = try #require(episode(#"""
        { "ok": true, "episode": {
            "slug": "ep-1", "kind": "episode", "number": 1, "title": { "en": "One" }, "track": "movement",
            "starts_at": "2026-10-06T10:30:00Z", "duration_seconds": 1800, "audio_url": "https://cdn.example.com/1.mp3",
            "has": { "research": true }, "member": true, "video_url": "ftp://nope",
            "show_notes": { "en": { "summary": "Sum", "chapters": [ { "start": "00:00:00", "title": "Welcome" }, { "start": "3m", "title": "Bad" },
                                     { "start": "00:03:40", "title": " " } ], "key_actions": ["a", "", 3] },
                            "fr": null },
            "research": { "en": { "synthesis": { "know": ["k"], "likely": [], "uncertain": ["u"] },
                                  "references": [ { "pmid": 12345678, "title": "", "journal": "J", "year": 2024, "authors": "A" },
                                                  { "pmid": "", "title": "" } ] },
                          "fr": { "synthesis": {}, "references": [] } },
            "article": { "en": { "title": "T", "intro": "", "sections": [] } },
            "guide": { "en": { "summary": "", "experiment": { "title": "Walk", "goal": "g",
                         "days": [ { "day": 2, "action": "two" }, { "day": 1, "action": "one" }, { "day": 40, "action": "x" }, { "day": 3, "action": "" } ] } } },
            "faq": { "fr": { "items": [ { "question": "Q ?", "answer": "R" }, { "question": "", "answer": "x" } ] } }
        } }
        """#))
        #expect(ep.card.slug == "ep-1")
        #expect(ep.member)
        #expect(ep.videoURL == nil)
        let notes = try #require(ep.showNotes)
        #expect(notes.fr == notes.en)
        #expect(notes.en.chapters.map(\.title) == ["Welcome"])
        #expect(notes.en.keyActions == ["a"])
        let research = try #require(ep.research)
        // An empty French side is filled from the English one.
        #expect(research.fr == research.en)
        #expect(research.en.references.map(\.pmid) == ["12345678"])
        // An article with no intro and no sections is no article.
        #expect(ep.article == nil)
        let guide = try #require(ep.guide?.pick("en"))
        #expect(guide.experiment.days.map(\.day) == [1, 2])
        let faq = try #require(ep.faq?.pick("en"))
        #expect(faq.items.map(\.question) == ["Q ?"])
    }

    @Test func publicEpisodeWithoutDocuments() throws {
        let ep = try #require(episode(#"""
        { "ok": true, "episode": { "slug": "ep-1", "title": { "en": "One" }, "starts_at": "2026-10-06T10:30:00Z", "member": false } }
        """#))
        #expect(!ep.member)
        #expect(ep.card.kind == .episode)
        #expect(ep.research == nil && ep.article == nil && ep.guide == nil && ep.faq == nil && ep.showNotes == nil)
    }

    @Test func episodeGarbage() {
        #expect(episode(#"{ "ok": false, "error": "not_found" }"#) == nil)
        #expect(episode(#"{ "ok": true, "episode": null }"#) == nil)
        #expect(episode(#"{ "ok": true, "episode": { "slug": "ep-1" } }"#) == nil)
        #expect(episode("garbage") == nil)
    }
}
