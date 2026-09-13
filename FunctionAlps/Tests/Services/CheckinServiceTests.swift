import Foundation
import Testing
@testable import FunctionAlps

@Suite("CheckinService")
struct CheckinServiceTests {
    private let noon = Date(timeIntervalSince1970: 1_788_350_400) // 2026-09-02T12:00:00Z
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    private func answers(calm: Double) -> FunctionalAnswers {
        var a = FunctionalAnswers.blank
        a[.stress]?.sliders = ["calm": calm]
        return a
    }

    @Test func oneScoredMomentGoesToTheOneWriter() async throws {
        let backend = RecordingBackend()
        let service = CheckinService(backend: backend, calendar: utc, now: { noon })
        let saved = try await service.save(slot: .midday, answers: answers(calm: 58), catalogPills: ["drained": ["travel"]], patientId: "p1")
        #expect(saved?.stressScore == 58)
        #expect(backend.calls == ["submit:midday:2026-09-02"])
        let sent = try #require(backend.lastMoment)
        #expect(sent.slot == .midday && sent.stressScore == 58 && sent.pills["drained"] == ["travel"] && sent.submittedAt == noon)
    }

    /// The roll-up the RPC performs, as the phone's reference implementation still computes it.
    @Test func theDayRollUpReferenceStillHolds() {
        let moment = CheckinEngine.momentFromAnswers(slot: .midday, answers: answers(calm: 58), catalogPills: [:], note: nil, submittedAt: noon)
        let patch = CheckinEngine.daySummaryPatch([moment], existing: DailyCheckinCarry(recovery: 7, sleepOverall: 88, sleep: 5), completedAt: noon)
        #expect(patch.stressScore == 58)
        #expect(patch.legacyStress == 3)
        #expect(patch.recovery == 7)
        #expect(patch.sleep == nil) // no sleep answer today → every sleep column left out
        #expect(CheckinEngine.momentEvents(moment).map(\.dimension) == ["stress"])
    }

    @Test func nothingAnsweredSavesNothing() async throws {
        let backend = RecordingBackend()
        let service = CheckinService(backend: backend, calendar: utc, now: { noon })
        let saved = try await service.save(slot: .evening, answers: .blank, catalogPills: [:], patientId: "p1")
        #expect(saved == nil)
        #expect(backend.calls.isEmpty)
    }

    @Test func summaryUsesEveryMomentOfTheDay() {
        let day = [
            CheckinMoment(slot: .morning, submittedAt: noon, energyOverall: 40, sleepOverall: 79),
            CheckinMoment(slot: .midday, submittedAt: noon, energyOverall: 100),
        ]
        let patch = CheckinEngine.daySummaryPatch(day, existing: nil, completedAt: noon)
        #expect(patch.energyOverall == 70)       // median of [40, 100]
        #expect(patch.sleep?.sleepOverall == 79) // the morning's night carried through
    }

    @Test func slotAndDayFollowTheLocalClock() {
        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-09-02 00:30 Zurich == 2026-09-01 22:30 UTC — files under the 2nd, in the morning slot.
        let service = CheckinService(backend: RecordingBackend(), calendar: zurich, now: { Date(timeIntervalSince1970: 1_788_301_800) })
        #expect(service.today == "2026-09-02")
        #expect(service.currentSlot == .morning)
    }
}
