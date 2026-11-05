import Foundation
import Testing
@testable import FunctionAlps

@Suite("Foundation Track — the day card's sections (track_day.card_*)")
struct TrackDayCardTests {
    /// `card_en` of day 3 and day 8, copied from supabase/migrations/20261006_foundation_track_day_card_content.sql.
    private static let day3 = #"""
{"today": [{"label": "What it is", "text": "Not sport: your functional capacity. How easily your body does what your life asks of it: getting up, carrying, climbing stairs, hiking."}, {"label": "Why it matters", "text": "Capacity is built or lost by what you do every day. Long hours of sitting slowly take it away; small, regular movement keeps it and builds it."}, {"label": "How we use it", "text": "Your answers set the right starting level for you and keep every movement we suggest safe. We start with little and often."}], "try_label": "First thing to try · your morning grows, your evening begins", "tip": "No time for an exercise snack? Take the stairs once. That counts.", "evolve": [{"when": "Tomorrow", "text": "5 minutes of daylight; your phone sleeps outside the bedroom."}, {"when": "Day 7", "text": "Your minute of movement becomes a 5-minute flow, and the exercise snack becomes daily."}, {"when": "Days 10–12", "text": "Easy strength, then a 10-minute morning flow."}], "library": [{"kind": "Lesson", "title": "Exercise snacks: small signals that add up"}], "pillar": "Pillar 2 · Movement"}
"""#
    private static let day8 = #"""
{"today": "Protein is your body's building material: muscle, bones, skin, your immune system. Your body can't store it the way it stores fat or sugar, so it needs some regularly across the day, and more as we age to keep our muscle. Many people eat little in the morning and most at night. Today, protein moves to breakfast.", "try_label": "New today", "tip": "Boil a few eggs for the week, or keep Greek yogurt in the fridge: breakfast protein in one minute.", "evolve": [{"when": "Tomorrow", "text": "Lunch: protein, vegetables, complex carbs, and your after-lunch walk doubles to 10 minutes."}, {"when": "Day 10", "text": "Easy strength."}], "library": [{"kind": "Infographic", "title": "Protein through the day"}]}
"""#

    private func json(_ text: String) throws -> JSONValue { try TrackJSON.decode(JSONValue.self, from: Data(text.utf8)) }

    @Test("Day 3: pillar, Today in three parts, try label, tip, how it evolves, a library item without a slug")
    func parts() throws {
        let card = try #require(TrackDayCard.decode(try json(Self.day3)))
        #expect(card.pillar == "Pillar 2 · Movement")
        guard case .parts(let parts)? = card.today else { Issue.record("expected parts"); return }
        #expect(parts.map(\.label) == ["What it is", "Why it matters", "How we use it"])
        #expect(parts[0].text.hasPrefix("Not sport: your functional capacity."))
        #expect(card.tryLabel == "First thing to try · your morning grows, your evening begins")
        #expect(card.tip == "No time for an exercise snack? Take the stairs once. That counts.")
        #expect(card.evolve.map(\.when) == ["Tomorrow", "Day 7", "Days 10–12"])
        #expect(card.library == [TrackDayCard.LibraryItem(kind: "Lesson", title: "Exercise snacks: small signals that add up")])
        #expect(card.openableLibrary.isEmpty)
    }

    @Test("Day 8: Today as one paragraph, no pillar")
    func paragraph() throws {
        let card = try #require(TrackDayCard.decode(try json(Self.day8)))
        #expect(card.pillar == nil)
        guard case .paragraph(let text)? = card.today else { Issue.record("expected a paragraph"); return }
        #expect(text.hasPrefix("Protein is your body's building material"))
        #expect(card.tryLabel == "New today")
        #expect(card.evolve.count == 2)
        #expect(card.library.first?.kind == "Infographic")
    }

    @Test("Optional keys may be missing; blank or malformed parts are left out")
    func optionalKeys() throws {
        let only = try #require(TrackDayCard.decode(try json(#"{"today": "Just a paragraph."}"#)))
        #expect(only.today == .paragraph("Just a paragraph."))
        #expect(only.pillar == nil && only.tryLabel == nil && only.tip == nil && only.evolve.isEmpty && only.library.isEmpty)

        let partial = try #require(TrackDayCard.decode(try json(#"{"today": [{"label": "What it is"}], "tip": "Take the stairs.", "evolve": [{"when": "Tomorrow"}, {"when": "Day 7", "text": "More."}]}"#)))
        #expect(partial.today == nil)
        #expect(partial.tip == "Take the stairs.")
        #expect(partial.evolve == [TrackDayCard.Step(when: "Day 7", text: "More.")])
    }

    @Test("Malformed or empty input is no card at all (the plain layout stays)")
    func malformed() throws {
        #expect(TrackDayCard.decode(nil) == nil)
        #expect(TrackDayCard.decode(try json(#""a string""#)) == nil)
        #expect(TrackDayCard.decode(try json("[]")) == nil)
        #expect(TrackDayCard.decode(try json("{}")) == nil)
        #expect(TrackDayCard.decode(try json(#"{"today": 3, "evolve": "soon", "library": [{"kind": "Lesson"}], "tip": "   ", "try_label": null}"#)) == nil)
    }

    @Test("Library: only items with a slug can be opened")
    func librarySlugs() throws {
        let card = try #require(TrackDayCard.decode(try json(#"""
        {"library": [{"kind": "Lesson", "title": "Exercise snacks", "slug": "exercise-snacks"}, {"kind": "Infographic", "title": "Not made yet"},
                     {"kind": "Lesson", "title": "Blank slug", "slug": "  "}, {"kind": "Lesson", "slug": "no-title"}]}
        """#)))
        #expect(card.library.map(\.title) == ["Exercise snacks", "Not made yet", "Blank slug"])
        #expect(card.openableLibrary.map(\.slug) == ["exercise-snacks"])
    }

    @Test("French card when the app is French and the day has one; English otherwise; the other as a fallback")
    func language() {
        let en = TrackDayCard(today: .paragraph("English"))
        let fr = TrackDayCard(today: .paragraph("Français"))
        var day = TrackDay(day: 8, titleEn: "Protein first")
        day.cardEn = en
        day.cardFr = fr
        #expect(TrackLogic.card(day, locale: "fr") == fr)
        #expect(TrackLogic.card(day, locale: "en") == en)
        day.cardFr = nil
        #expect(TrackLogic.card(day, locale: "fr") == en)
        day.cardEn = nil
        #expect(TrackLogic.card(day, locale: "en") == nil)
        day.cardFr = fr
        #expect(TrackLogic.card(day, locale: "en") == fr)
    }

    @Test("The row: card columns and how-to lines decode verbatim; the infographic is https only")
    func row() throws {
        let rows = Data("""
        [{"day": 3, "title_en": "How you move", "actions": [{"key": "move_1min", "moment": "morning", "face": "standard", "new": true,
           "title_en": "1 minute of gentle movement", "how_en": "Roll your shoulders, circle your hips, a few slow squats."}],
          "push": {}, "card_en": \(Self.day3), "card_fr": null, "image_url": null, "image_alt_en": null},
         {"day": 8, "title_en": "Protein first", "actions": [], "push": {}, "card_en": {"tip": "   "}, "card_fr": \(Self.day8),
          "image_url": "https://example.com/protein.png", "image_alt_en": "Protein through the day", "image_alt_fr": "Les protéines dans la journée"}]
        """.utf8)
        let days = try TrackJSON.decode([TrackDayWire].self, from: rows).map(\.day)
        #expect(days[0].cardEn?.pillar == "Pillar 2 · Movement")
        #expect(days[0].cardFr == nil)
        #expect(days[0].actions.first?.howEn == "Roll your shoulders, circle your hips, a few slow squats.")
        #expect(TrackLogic.infographic(days[0], locale: "en") == nil)
        #expect(days[1].cardEn == nil)                                   // a blank card is no card
        #expect(TrackLogic.card(days[1], locale: "en")?.tryLabel == "New today")
        let image = try #require(TrackLogic.infographic(days[1], locale: "fr"))
        #expect(image.url.absoluteString == "https://example.com/protein.png")
        #expect(image.alt == "Les protéines dans la journée")
        var http = days[1]
        http.imageUrl = "http://example.com/protein.png"
        #expect(TrackLogic.infographic(http, locale: "en") == nil)
    }
}
