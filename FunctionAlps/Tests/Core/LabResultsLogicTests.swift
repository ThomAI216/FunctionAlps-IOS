import Foundation
import Testing
@testable import FunctionAlps

/// Copy 3 of the member grouping (CLINICAL `groupMemberRows`, Expo `groupResults`). The fixture is the
/// wire shape of `get_member_lab_results()` from CLINICAL migration 223 — re-fixture from the
/// migration, never from another copy.
@Suite("Lab results — the member contract, grouped")
struct LabResultsLogicTests {
    /// Two approved releases of one member: September (fr, 3 lines + 1 line with an unknown status)
    /// and March (fr, 1 line). Rows arrive out of order on purpose.
    static let fixture = """
    [
     {"release_id":"rel-sep","lab_run_id":"run-sep","sampled_at":"2026-09-12T00:00:00+00:00","language":"fr",
      "headline_md":"Votre fer remonte, la vitamine D reste basse","what_we_saw_md":"Ferritine et vitamine D.","what_it_means_md":"Le fer se reconstitue.","what_we_do_next_md":"On garde la vitamine D.",
      "phase_update":{"title":"Phase 2 — Construire l’endurance","summary_md":"Votre plan passe en phase 2."},
      "next_steps":[{"kind":"recheck","statement_md":"Contrôle de la ferritine dans trois mois."},{"kind":"plan","statement_md":"   "},{"kind":"plan","statement_md":"Vitamine D poursuivie."}],
      "biomarker_result_id":"m-vitd","label":"Vitamine D","value":"18","unit":"ng/mL","status":"out_of_range",
      "why_it_matters_md":"La vitamine D soutient l’immunité.","in_your_plan_md":"Poursuivre 2000 UI.","patient_safe_explanation":"Un niveau bas est fréquent en hiver.","sort_order":2},
     {"release_id":"rel-sep","lab_run_id":"run-sep","sampled_at":"2026-09-12T00:00:00+00:00","language":"fr",
      "headline_md":"Votre fer remonte, la vitamine D reste basse","what_we_saw_md":"Ferritine et vitamine D.","what_it_means_md":"Le fer se reconstitue.","what_we_do_next_md":"On garde la vitamine D.",
      "phase_update":{"title":"Phase 2 — Construire l’endurance","summary_md":"Votre plan passe en phase 2."},
      "next_steps":[{"kind":"recheck","statement_md":"Contrôle de la ferritine dans trois mois."},{"kind":"plan","statement_md":"   "},{"kind":"plan","statement_md":"Vitamine D poursuivie."}],
      "biomarker_result_id":"m-ferr","label":"Ferritine","value":"28","unit":"µg/L","status":"watch",
      "why_it_matters_md":"La ferritine est votre réserve de fer.","in_your_plan_md":null,"patient_safe_explanation":null,"sort_order":1},
     {"release_id":"rel-sep","lab_run_id":"run-sep","sampled_at":"2026-09-12T00:00:00+00:00","language":"fr",
      "headline_md":"Votre fer remonte, la vitamine D reste basse","what_we_saw_md":"Ferritine et vitamine D.","what_it_means_md":"Le fer se reconstitue.","what_we_do_next_md":"On garde la vitamine D.",
      "phase_update":{"title":"Phase 2 — Construire l’endurance","summary_md":"Votre plan passe en phase 2."},
      "next_steps":[{"kind":"recheck","statement_md":"Contrôle de la ferritine dans trois mois."},{"kind":"plan","statement_md":"   "},{"kind":"plan","statement_md":"Vitamine D poursuivie."}],
      "biomarker_result_id":"m-odd","label":"Ligne étrange","value":"1","unit":null,"status":"critical",
      "why_it_matters_md":"","in_your_plan_md":null,"patient_safe_explanation":null,"sort_order":4},
     {"release_id":"rel-mar","lab_run_id":"run-mar","sampled_at":"2026-03-02T00:00:00+00:00","language":"xx",
      "headline_md":"Un premier bilan rassurant","what_we_saw_md":"","what_it_means_md":"","what_we_do_next_md":"",
      "phase_update":null,"next_steps":[],
      "biomarker_result_id":"m-ferr-old","label":"ferritine ","value":"14","unit":"µg/L","status":"in_range",
      "why_it_matters_md":"","in_your_plan_md":null,"patient_safe_explanation":null,"sort_order":1},
     {"release_id":"rel-sep","lab_run_id":"run-sep","sampled_at":"2026-09-12T00:00:00+00:00","language":"fr",
      "headline_md":"Votre fer remonte, la vitamine D reste basse","what_we_saw_md":"Ferritine et vitamine D.","what_it_means_md":"Le fer se reconstitue.","what_we_do_next_md":"On garde la vitamine D.",
      "phase_update":{"title":"Phase 2 — Construire l’endurance","summary_md":"Votre plan passe en phase 2."},
      "next_steps":[{"kind":"recheck","statement_md":"Contrôle de la ferritine dans trois mois."},{"kind":"plan","statement_md":"   "},{"kind":"plan","statement_md":"Vitamine D poursuivie."}],
      "biomarker_result_id":"m-crp","label":"CRP","value":"0.8","unit":"mg/L","status":"in_range",
      "why_it_matters_md":"La CRP mesure l’inflammation.","in_your_plan_md":null,"patient_safe_explanation":null,"sort_order":3}
    ]
    """

    private func rows() throws -> [LabResultRow] {
        try JSON.decode([LabResultRow].self, from: Data(Self.fixture.utf8))
    }

    /// The `select=` list IS the contract: the 19 columns of migration 223's `returns table`, in its order.
    @Test func pinsTheMigrationsColumns() {
        #expect(LabResultRow.columns == [
            "release_id", "lab_run_id", "sampled_at", "language",
            "headline_md", "what_we_saw_md", "what_it_means_md", "what_we_do_next_md",
            "phase_update", "next_steps",
            "biomarker_result_id", "label", "value", "unit", "status",
            "why_it_matters_md", "in_your_plan_md", "patient_safe_explanation", "sort_order",
        ])
        #expect(LabResultRow.columns.count == 19)
    }

    @Test func decodesTheWireRow() throws {
        let decoded = try rows()
        #expect(decoded.count == 5)
        let vitd = try #require(decoded.first { $0.biomarkerResultId == "m-vitd" })
        #expect(vitd.sampledAt != nil)
        #expect(vitd.phaseUpdate?.title == "Phase 2 — Construire l’endurance")
        #expect(vitd.phaseUpdate?.summaryMd == "Votre plan passe en phase 2.")
        #expect(vitd.nextSteps?.count == 3)
        #expect(vitd.patientSafeExplanation == "Un niveau bas est fréquent en hiver.")
        let old = try #require(decoded.first { $0.biomarkerResultId == "m-ferr-old" })
        #expect(old.phaseUpdate == nil)
        #expect(old.nextSteps?.isEmpty == true)
    }

    @Test func groupsNewestFirstWithLinesInReleaseOrder() throws {
        let results = LabResultsLogic.group(try rows())
        #expect(results.map(\.releaseId) == ["rel-sep", "rel-mar"])
        let sep = results[0]
        // sort_order 1, 2, 3 — whatever order the rows arrived in; the "critical" line is dropped, not guessed.
        #expect(sep.markers.map(\.id) == ["m-ferr", "m-vitd", "m-crp"])
        #expect(sep.markers.map(\.status) == [.watch, .outOfRange, .inRange])
        #expect(sep.language == .fr)
        #expect(sep.headline == "Votre fer remonte, la vitamine D reste basse")
        #expect(sep.phaseUpdate == LabResult.PhaseUpdate(title: "Phase 2 — Construire l’endurance", summary: "Votre plan passe en phase 2."))
        // A blank statement is not a step.
        #expect(sep.nextSteps.map(\.statement) == ["Contrôle de la ferritine dans trois mois.", "Vitamine D poursuivie."])
        #expect(sep.nextSteps.map(\.kind) == ["recheck", "plan"])
        let mar = results[1]
        #expect(mar.language == .fr, "an unknown release language falls back to French, never to the phone")
        #expect(mar.phaseUpdate == nil)
        #expect(mar.nextSteps.isEmpty)
        #expect(mar.markers.count == 1)
        #expect(mar.markers[0].value == "14")
    }

    @Test func undatedReleaseSortsLast() throws {
        var decoded = try rows()
        let undated = LabResultRow(
            releaseId: "rel-none", labRunId: "run-none", sampledAt: nil, language: "en",
            headlineMd: "Undated", whatWeSawMd: nil, whatItMeansMd: nil, whatWeDoNextMd: nil, phaseUpdate: nil, nextSteps: nil,
            biomarkerResultId: "m-x", label: "X", value: "1", unit: nil, status: "in_range",
            whyItMattersMd: nil, inYourPlanMd: nil, patientSafeExplanation: nil, sortOrder: 1
        )
        decoded.insert(undated, at: 0)
        #expect(LabResultsLogic.group(decoded).map(\.releaseId) == ["rel-sep", "rel-mar", "rel-none"])
    }

    @Test func splitsAndCounts() throws {
        let sep = LabResultsLogic.group(try rows())[0]
        let split = LabResultsLogic.split(sep.markers)
        #expect(split.flagged.map(\.id) == ["m-ferr", "m-vitd"])
        #expect(split.inRange.map(\.id) == ["m-crp"])
        let counts = LabResultsLogic.counts(sep.markers)
        #expect(counts[.inRange] == 1)
        #expect(counts[.watch] == 1)
        #expect(counts[.outOfRange] == 1)
        #expect(LabResultsLogic.counts([]) == [.inRange: 0, .watch: 0, .outOfRange: 0])
    }

    /// The same marker in EARLIER releases only, matched by label (case- and space-insensitive), oldest first.
    @Test func earlierValuesLookBackOnly() throws {
        let results = LabResultsLogic.group(try rows())
        let history = LabResultsLogic.earlierValues(in: results, releaseId: "rel-sep", label: "Ferritine")
        #expect(history.count == 1)
        #expect(history[0].value == "14")
        #expect(history[0].unit == "µg/L")
        #expect(history[0].status == .inRange)
        // From the March release, September is the future: nothing earlier.
        #expect(LabResultsLogic.earlierValues(in: results, releaseId: "rel-mar", label: "Ferritine").isEmpty)
        // A marker only seen once has no history; an unknown release has none either.
        #expect(LabResultsLogic.earlierValues(in: results, releaseId: "rel-sep", label: "CRP").isEmpty)
        #expect(LabResultsLogic.earlierValues(in: results, releaseId: "rel-nope", label: "Ferritine").isEmpty)
        #expect(LabResultsLogic.earlierValues(in: results, releaseId: "rel-sep", label: "  ").isEmpty)
    }

    @Test func statusLabelsFollowTheReleaseLanguage() {
        #expect(LabResultCopy.forLanguage(.fr).statusLabel(.watch) == "À surveiller")
        #expect(LabResultCopy.forLanguage(.en).statusLabel(.outOfRange) == "Out of range")
        #expect(LabResultCopy.forLanguage(.it).statusLabel(.inRange) == "Nella norma")
        #expect(LabResultCopy.forLanguage(.de).inRange(3) == "3 im Bereich")
        #expect(LabResultCopy.forLanguage(.fr).inRange(3) == "3 dans la zone")
    }

    /// The calendar day in UTC: a sample taken late on the 12th stays the 12th on every phone.
    @Test func formatsTheSampleDayInUTC() throws {
        let late = try #require(ISO8601.parse("2026-09-12T23:30:00+00:00"))
        #expect(LabSampleDate.format(late, language: .fr) == "12 septembre 2026")
        #expect(LabSampleDate.format(late, language: .en) == "12 September 2026")
        #expect(LabSampleDate.format(late, language: .it) == "12 settembre 2026")
        #expect(LabSampleDate.format(late, language: .de) == "12. September 2026")
        let first = try #require(ISO8601.parse("2026-01-01T00:00:00+00:00"))
        #expect(LabSampleDate.format(first, language: .fr) == "1 janvier 2026")
        #expect(LabSampleDate.format(nil, language: .fr) == "")
    }
}
