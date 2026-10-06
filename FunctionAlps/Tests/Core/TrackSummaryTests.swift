import Foundation
import Testing
@testable import FunctionAlps

@Suite("Foundation Track — the approved day-7 summary and where its notification leads")
struct TrackSummaryTests {
    /// Built from CLINICAL's `SummaryContentV1` (lib/foundation-track/summary-content.ts), with the edges it allows:
    /// a null section, a blank one, a goal without a label, an action without a day, a null range.
    private static let v1 = """
    {"version": 1, "audience": "member", "language": "en",
     "learned": {"context": "You work regular hours and sit most of the day.", "food": "You usually eat three meals.",
                 "movement": null, "sleep": "  ", "stress": "Work is the main source of your stress."},
     "goals": {"source": "day6", "items": [{"value": "energy", "label": "More energy"}, {"value": "sleep", "label": "Better sleep"}, {"value": "x"}]},
     "week2_actions": [
       {"key": "dim_lights", "day": 11, "moment": "evening", "title": "Dim the lights after 21:00"},
       {"key": "walk_after_breakfast", "day": 8, "moment": null, "title": "A 10-minute walk after breakfast"},
       {"key": "protein_breakfast", "day": 8, "moment": "morning", "title": "Protein at breakfast"},
       {"key": "sit_to_stands", "day": 10, "moment": "day", "title": "10 sit-to-stands"},
       {"key": "lunch_plate", "day": 9, "moment": "midday", "title": "Vegetables on half the plate"},
       {"key": "broken", "title": "No day"}],
     "energy_kcal": {"low": 2250, "high": 2450},
     "protein_g": null,
     "provenance": {"responses": ["r1", "r2"], "profile": "nb_patient_app_profiles", "track_days": "8-14"},
     "ai_derived": ["context", "food", "stress"]}
    """

    private func json(_ text: String) throws -> JSONValue {
        try TrackJSON.decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test("Content v1: sections in order (null and blank skipped), goals, week-2 actions by day then moment, ranges")
    func decodesV1() throws {
        let content = try #require(TrackSummaryContent.decode(try json(Self.v1)))
        #expect(content.language == "en")
        #expect(content.learned.map(\.key) == ["context", "food", "stress"])
        #expect(content.learned.first?.text == "You work regular hours and sit most of the day.")
        #expect(content.goalsSource == "day6")
        #expect(content.goals.map(\.label) == ["More energy", "Better sleep"])
        #expect(content.weekTwoActions.map(\.key) == ["protein_breakfast", "walk_after_breakfast", "lunch_plate", "sit_to_stands", "dim_lights"])
        #expect(content.weekTwoActions.first?.moment == .morning)
        #expect(content.weekTwoActions[1].moment == nil)
        #expect(content.energyKcal == TrackSummaryContent.Range(low: 2250, high: 2450))
        #expect(content.proteinG == nil)
        #expect(!content.isEmpty)
    }

    @Test("Another version, another audience or another shape is not rendered at all")
    func unknownIsHidden() throws {
        #expect(TrackSummaryContent.decode(try json(#"{"version": 2, "audience": "member", "learned": {"food": "x"}}"#)) == nil)
        #expect(TrackSummaryContent.decode(try json(#"{"version": 1, "audience": "staff", "learned": {"food": "x"}}"#)) == nil)
        #expect(TrackSummaryContent.decode(try json(#"{"audience": "member"}"#)) == nil)
        #expect(TrackSummaryContent.decode(try json(#"["version", 1]"#)) == nil)
        #expect(TrackSummaryContent.decode(nil) == nil)
        // v1 with nothing usable decodes, and says it is empty (the view then shows its empty state).
        let bare = TrackSummaryContent.decode(try json(#"{"version": 1, "learned": null, "goals": null, "week2_actions": [], "energy_kcal": {"low": 0, "high": 0}}"#))
        #expect(bare?.isEmpty == true)
    }

    @Test("The row: an approved v1 summary decodes; an unreadable content version leaves no summary")
    func row() throws {
        let rows = Data("""
        [{"id": "s1", "day": 7, "approved_at": "2026-10-13T09:12:00.500+00:00", "content": \(Self.v1)},
         {"id": "s2", "day": 7, "approved_at": null, "content": {"version": 9}}]
        """.utf8)
        let decoded = try TrackJSON.decode([TrackSummaryWire].self, from: rows)
        #expect(decoded[0].summary?.id == "s1")
        #expect(decoded[0].summary?.approvedAt != nil)
        #expect(decoded[0].summary?.content.learned.count == 3)
        #expect(decoded[1].summary == nil)
    }

    @Test("A notification row routes by its own route, else by its item kind; the summary item opens the summary")
    func routing() throws {
        let summary = try json(#"{"items": [{"kind": "track_summary", "track_summary_id": "s1", "track_code": "foundation_v1"}], "count": 1}"#)
        #expect(NotificationRouting.route(data: summary)?.absoluteString == "functionalps://foundation/summary")
        // Coalesced with another report item: the kind the app knows still wins.
        let coalesced = try json(#"{"items": [{"kind": "ai_output", "ai_output_id": "a", "output_type": "x"}, {"kind": "track_summary", "track_summary_id": "s1", "track_code": "foundation_v1"}], "count": 2}"#)
        #expect(NotificationRouting.route(data: coalesced)?.absoluteString == NotificationRouting.trackSummary)
        #expect(NotificationRouting.route(data: try json(#"{"route": "functionalps://messages", "collapse": "messages"}"#))?.absoluteString == "functionalps://messages")
        #expect(NotificationRouting.route(data: try json(#"{"route": "https://example.com", "items": []}"#)) == nil)
        #expect(NotificationRouting.route(data: try json(#"{"items": [{"kind": "report", "report_id": "r", "report_event": "new_report"}]}"#)) == nil)
        #expect(NotificationRouting.route(data: nil) == nil)
    }

    @Test("functionalps://foundation/summary opens the summary on Home; foundation alone opens Home")
    @MainActor
    func routerParse() throws {
        let router = AppRouter()
        router.tab = .profile
        router.open(try #require(URL(string: "functionalps://foundation/summary")))
        #expect(router.tab == .home)
        #expect(router.homePath == [.trackSummary])
        router.open(try #require(URL(string: "functionalps://foundation")))
        #expect(router.homePath.isEmpty)
    }
}
