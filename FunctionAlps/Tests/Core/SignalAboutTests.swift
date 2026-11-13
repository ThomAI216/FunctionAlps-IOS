import Foundation
import Testing
@testable import FunctionAlps

/// The signal explanations (owner, 2026-11-11): the content decodes tolerantly, the newest approved version wins, evidence
/// maps to the owner's badge colours, and the pure helpers (action match, related reading, the map's geometry) behave.
@Suite("Signal explanations — decoding, newest version, evidence styles, matching, map")
struct SignalAboutTests {
    private static let full = """
    {
      "title": "About energy",
      "what_it_is": "How much usable get-up-and-go you have.",
      "feels_high": "Steady through the day.",
      "feels_low": "Heavy, slow.",
      "feels_high_label": "Good",
      "card_text": "Energy is influenced by how you slept.",
      "influences": [
        {"icon": "sleep", "line": "Sleep sets the ceiling.", "why": "Sleep loss slows reaction.", "evidence": "strong"},
        {"icon": "water", "line": "Not drinking enough dulls energy.", "why": "Small deficits matter.", "evidence": "moderate"}
      ],
      "connections": [
        {"to": "mood", "direction": "out", "label": "effort", "evidence": "moderate"},
        {"to": "sleep", "direction": "in", "label": "alertness"}
      ],
      "actions": [{"text": "Walk for 10 minutes after a meal.", "habit_hint": "walk_after_meal"}],
      "plate_intro": "Energy is shaped by what's on your plate.",
      "plate": [{"key": "carbs", "title": "Carbs", "line": "Refined carbs are sluggish.", "evidence": "emerging"}],
      "plate_rule": {"title": "The practical rule", "line": "Combine protein, fibre and fat.", "evidence": "moderate"},
      "safety_line": "If this stays low for weeks, talk to your practitioner.",
      "sources": ["Lim & Dinges 2010 · Psychol Bull", "  ", "Palmer 2024 · Psychol Bull"]
    }
    """

    private func decode(_ json: String) throws -> SignalExplanation.Content {
        try JSON.decode(SignalExplanation.Content.self, from: Data(json.utf8))
    }

    @Test("A full content object decodes, snake_case keys included")
    func decodesFull() throws {
        let c = try decode(Self.full)
        #expect(c.title == "About energy")
        #expect(c.whatItIs == "How much usable get-up-and-go you have.")
        #expect(c.feelsHigh == "Steady through the day." && c.feelsLow == "Heavy, slow.")
        #expect(c.feelsHighLabel == "Good" && c.feelsLowLabel == nil)
        #expect(c.cardText == "Energy is influenced by how you slept.")
        #expect(c.influences.count == 2 && c.influences[0].icon == "sleep" && c.influences[1].evidence == "moderate")
        #expect(c.connections.map(\.to) == ["mood", "sleep"] && c.connections[1].evidence == "")
        #expect(c.actions == [.init(text: "Walk for 10 minutes after a meal.", habitHint: "walk_after_meal")])
        #expect(c.plate.count == 1 && c.plate[0].key == "carbs")
        #expect(c.plateRule?.line == "Combine protein, fibre and fat.")
        #expect(c.safetyLine == "If this stays low for weeks, talk to your practitioner.")
        #expect(c.sources == ["Lim & Dinges 2010 · Psychol Bull", "Palmer 2024 · Psychol Bull"])
        #expect(c.isUsable)
    }

    @Test("Missing optional fields and arrays decode as empty, never as a failure")
    func decodesMissing() throws {
        let c = try decode(#"{"what_it_is": "A summary."}"#)
        #expect(c.title == "" && c.feelsHigh == "" && c.cardText == "")
        #expect(c.influences.isEmpty && c.connections.isEmpty && c.actions.isEmpty && c.plate.isEmpty && c.sources.isEmpty)
        #expect(c.plateRule == nil && c.safetyLine == nil && c.feelsHighLabel == nil)
        #expect(c.isUsable)
        #expect(try decode("{}").isUsable == false)
    }

    @Test("A malformed element is dropped; the rest of the array stays")
    func dropsMalformedElements() throws {
        let c = try decode("""
        {"what_it_is": "x",
         "influences": [{"line": "Good one", "evidence": "strong"}, {"icon": "sleep"}, "not an object", {"line": "Second", "why": "Because"}],
         "actions": [{"habit_hint": "walk"}, {"text": "Do this"}],
         "connections": [{"label": "no target"}, {"to": "mood"}]}
        """)
        #expect(c.influences.map(\.line) == ["Good one", "Second"])
        #expect(c.actions.map(\.text) == ["Do this"] && c.actions[0].habitHint == nil)
        #expect(c.connections.map(\.to) == ["mood"] && c.connections[0].direction == "out")
    }

    @Test("A whole row decodes the way PostgREST sends it")
    func decodesRow() throws {
        let rows = try JSON.decode([SignalExplanation].self, from: Data("""
        [{"signal": "sleep", "locale": "en", "version": 2, "content": {"what_it_is": "Sleep."}}]
        """.utf8))
        #expect(rows.count == 1 && rows[0].signal == "sleep" && rows[0].version == 2 && rows[0].content.whatItIs == "Sleep.")
    }

    @Test("The newest version of each signal is the one kept")
    func newestVersion() {
        func row(_ signal: String, _ version: Int, _ text: String) -> SignalExplanation {
            var content = SignalExplanation.Content()
            content.whatItIs = text
            return SignalExplanation(signal: signal, locale: "en", version: version, content: content)
        }
        let kept = SignalExplanation.newestPerSignal([row("sleep", 1, "old"), row("sleep", 3, "newest"), row("energy", 1, "e1"), row("sleep", 2, "mid")])
        #expect(kept["sleep"]?.content.whatItIs == "newest" && kept["sleep"]?.version == 3)
        #expect(kept["energy"]?.content.whatItIs == "e1")
        #expect(kept.count == 2)
        // Rows arrive newest first from the backend: the order must not matter.
        #expect(SignalExplanation.newestPerSignal([row("sleep", 3, "newest"), row("sleep", 1, "old")])["sleep"]?.version == 3)
    }

    @Test("Strong is a filled green badge, moderate blue, emerging purple (owner, 2026-11-11)")
    func evidenceBadgeStyles() {
        #expect(SignalEvidence.strong.badge == .init(backgroundHex: 0x4A8A5C, backgroundOpacity: 1, foregroundHex: 0xFFFFFF))
        #expect(SignalEvidence.moderate.badge == .init(backgroundHex: 0x4F86C6, backgroundOpacity: 0.18, foregroundHex: 0x1D4E89))
        #expect(SignalEvidence.emerging.badge == .init(backgroundHex: 0x8E7CC3, backgroundOpacity: 0.18, foregroundHex: 0x5B4A9E))
    }

    @Test("Evidence words map to a level; mixed levels read as moderate; anything unknown as emerging")
    func evidenceMapping() {
        #expect(SignalEvidence(raw: "strong") == .strong)
        #expect(SignalEvidence(raw: "Strong") == .strong)
        #expect(SignalEvidence(raw: "moderate") == .moderate)
        #expect(SignalEvidence(raw: "moderate-strong") == .moderate)
        #expect(SignalEvidence(raw: "strong-moderate") == .moderate)
        #expect(SignalEvidence(raw: "emerging") == .emerging)
        #expect(SignalEvidence(raw: "") == .emerging)
        #expect(SignalEvidence(raw: nil) == .emerging)
        #expect(SignalEvidence(raw: "banana") == .emerging)
    }

    @Test("The map's line is solid for strong, dashed for moderate, dotted for emerging")
    func evidenceLines() {
        #expect(SignalEvidence.strong.line.dash.isEmpty)
        #expect(SignalEvidence.moderate.line.dash == [5, 3.2])
        #expect(SignalEvidence.emerging.line.roundCap && SignalEvidence.emerging.line.dash.count == 2)
    }

    // MARK: Action match

    private func card(_ id: String, _ title: String, fr: String? = nil) -> ActionCardRow {
        var row = ActionCardRow(id: id, title: title)
        row.titleFr = fr
        return row
    }

    @Test("A habit hint finds the first bank card whose title holds one of its words, in either language")
    func actionMatch() {
        let bank = [card("a", "Protein snack mid-afternoon"), card("b", "A 10-minute walk after lunch"), card("c", "Morning circadian routine", fr: "Routine circadienne du matin"),
                    card("d", "Five minutes of daylight", fr: "Cinq minutes de lumière du jour")]
        #expect(SignalActionMatch.card(for: "walk", in: bank)?.id == "b")
        #expect(SignalActionMatch.card(for: "walk_after_meal", in: bank)?.id == "b")
        #expect(SignalActionMatch.card(for: "daylight", in: bank)?.id == "d")
        #expect(SignalActionMatch.card(for: "protein", in: bank)?.id == "a")
        #expect(SignalActionMatch.card(for: "WALK", in: bank)?.id == "b")
    }

    @Test("No matching card — or a hint the app does not know — means no card (the caller opens the bank)")
    func actionNoMatch() {
        let bank = [card("a", "Protein snack mid-afternoon")]
        #expect(SignalActionMatch.card(for: "breathwork", in: bank) == nil)
        #expect(SignalActionMatch.card(for: "lowest_signal", in: bank) == nil)
        #expect(SignalActionMatch.card(for: nil, in: bank) == nil)
        #expect(SignalActionMatch.card(for: "walk", in: []) == nil)
        // A word start, not a substring: "eau" must not find "bureau".
        #expect(SignalActionMatch.card(for: "hydration", in: [card("x", "Aménager le bureau")]) == nil)
        #expect(SignalActionMatch.card(for: "hydration", in: [card("y", "Un verre d’eau au réveil")])?.id == "y")
    }

    // MARK: Related reading

    @Test("Related reading: open reads of the signal's pillar, at most two, none for the score")
    func relatedReading() {
        let list = [
            LibraryArticle(slug: "n1", title: "Nutrition one", tags: ["nutrition"]),
            LibraryArticle(slug: "s1", title: "Sleep one", tags: ["sommeil"]),
            LibraryArticle(slug: "s2", title: "Sleep two", tags: ["pillar:sommeil"]),
            LibraryArticle(slug: "s3", title: "Sleep three", tags: ["sommeil"]),
            LibraryArticle(slug: "s4", title: "Locked sleep", tags: ["sommeil"], locked: true),
        ]
        #expect(SignalRelated.articles(for: .sleep, in: list).map(\.slug) == ["s1", "s2"])
        #expect(SignalRelated.articles(for: .digestion, in: list).map(\.slug) == ["n1"])
        #expect(SignalRelated.articles(for: .score, in: list).isEmpty)
        #expect(SignalRelated.articles(for: .stress, in: list).isEmpty)
        #expect(SignalRelated.articles(for: .sleep, in: list, limit: 0).isEmpty)
    }

    // MARK: The map

    @Test("The map puts this signal in the centre and the other signals around it; the score has all six")
    func mapNodes() {
        let sleep = SignalMapLayout.make(centre: "sleep", connections: [])
        #expect(sleep.nodes.count == 6 && sleep.nodes.filter(\.isCentre).map(\.key) == ["sleep"])
        #expect(!sleep.nodes.contains { !$0.isCentre && $0.key == "sleep" })
        let score = SignalMapLayout.make(centre: "score", connections: [])
        #expect(score.nodes.count == 7 && score.nodes.filter(\.isCentre).map(\.key) == ["score"])
    }

    @Test("An out arrow leaves the centre, an in arrow arrives; unknown or self targets and repeats are skipped")
    func mapEdges() {
        let layout = SignalMapLayout.make(centre: "energy", connections: [
            .init(to: "mood", direction: "out", label: "effort", evidence: "moderate"),
            .init(to: "sleep", direction: "in", label: "alertness", evidence: "strong"),
            .init(to: "mood", direction: "out", label: "again"),
            .init(to: "energy", direction: "out", label: "self"),
            .init(to: "weather", direction: "out", label: "unknown"),
            .init(to: "focus", direction: "both", label: "both"),
        ])
        #expect(layout.edges.count == 3)
        #expect(layout.edges[0].from == "energy" && layout.edges[0].to == "mood" && layout.edges[0].evidence == .moderate)
        #expect(layout.edges[1].from == "sleep" && layout.edges[1].to == "energy" && layout.edges[1].evidence == .strong)
        #expect(layout.edges[2].bothEnds && layout.edges[2].heads.count == 2)
        #expect(layout.edges[0].heads.count == 1 && layout.edges[0].evidence.line.dash == [5, 3.2])
    }

    @Test("Every edge ends on its target's pill, and its label sits on the curve")
    func mapGeometry() throws {
        let layout = SignalMapLayout.make(centre: "sleep", connections: [.init(to: "energy", direction: "out", label: "alertness", evidence: "strong")])
        let edge = try #require(layout.edges.first)
        let target = try #require(layout.nodes.first { $0.key == "energy" })
        let tip = try #require(edge.heads.first).tip
        // The tip is just outside the target's rectangle (a 3-point margin), never inside the centre pill.
        #expect(abs(tip.x - target.center.x) <= target.half.width + 3.5 && abs(tip.y - target.center.y) <= target.half.height + 3.5)
        let centre = try #require(layout.nodes.first { $0.isCentre })
        #expect(!(abs(tip.x - centre.center.x) < centre.half.width && abs(tip.y - centre.center.y) < centre.half.height))
        #expect(edge.labelPoint.x > 0 && edge.labelPoint.x < layout.size.width && edge.labelPoint.y > 0 && edge.labelPoint.y < layout.size.height)
    }

    @Test("The score's arrows are straight; a signal's are bent so a pair of opposite arrows do not overlap")
    func mapCurves() throws {
        let score = SignalMapLayout.make(centre: "score", connections: [.init(to: "sleep", direction: "in", label: "1/6", evidence: "strong")])
        let straight = try #require(score.edges.first)
        let mid = CGPoint(x: (straight.start.x + straight.end.x) / 2, y: (straight.start.y + straight.end.y) / 2)
        #expect(abs(mid.x - straight.control.x) < 4 && abs(mid.y - straight.control.y) < 4)
        let pair = SignalMapLayout.make(centre: "sleep", connections: [.init(to: "stress", direction: "out", label: "a"), .init(to: "stress", direction: "in", label: "b")])
        #expect(pair.edges.count == 2 && pair.edges[0].control != pair.edges[1].control)
    }

    @Test("Seven keys have a page, and the score is the only one that is not a Trends signal")
    func keys() {
        #expect(SignalAboutKey.allCases.count == 7)
        #expect(SignalAboutKey.allCases.filter { $0.trendSignal == nil } == [.score])
        #expect(SignalAboutKey(rawValue: "digestion") == .digestion && SignalAboutKey(rawValue: "nope") == nil)
    }
}
