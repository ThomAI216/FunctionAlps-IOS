import Foundation
import Testing
@testable import FunctionAlps

/// The gut write is two steps in a fixed order (the day row upsert, then the events). It is NOT run concurrently with the
/// check-in RPC: both write `patient_daily_checkins` for the day, and the events insert is not idempotent.
@Suite("GutService save")
struct GutServiceSaveTests {
    private let noon = Date(timeIntervalSince1970: 1_788_350_400) // 2026-09-02T12:00:00Z
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    private func answered() -> GutAnswerSet {
        var a = GutAnswerSet.blank
        a[.comfort]?.sliders = ["comfort": 70]
        return a
    }

    @Test func theDayRowIsWrittenBeforeTheEventsAndHomeIsMarkedStaleAfterBoth() async throws {
        let backend = RecordingBackend()
        let freshness = DataFreshness()
        let service = GutService(backend: backend, calendar: utc, now: { noon }, freshness: freshness)
        let wrote = try await service.save(patientId: "p1", answers: answered(), notes: nil)
        #expect(wrote)
        #expect(backend.calls == ["gutUpsert:2026-09-02", "events:1"])
        #expect(freshness.homeVersion == 1)
    }

    @Test func aFailedDayRowWritesNoEventsAndLeavesHomeFresh() async throws {
        let backend = RecordingBackend()
        backend.gutUpsertFails = true
        let freshness = DataFreshness()
        let service = GutService(backend: backend, calendar: utc, now: { noon }, freshness: freshness)
        await #expect(throws: AppError.self) { try await service.save(patientId: "p1", answers: answered(), notes: nil) }
        #expect(backend.calls == ["gutUpsert:2026-09-02"]) // no events: a retry cannot duplicate them
        #expect(freshness.homeVersion == 0)
    }

    @Test func nothingAnsweredWritesNothingAndBumpsNothing() async throws {
        let backend = RecordingBackend()
        let freshness = DataFreshness()
        let service = GutService(backend: backend, calendar: utc, now: { noon }, freshness: freshness)
        let wrote = try await service.save(patientId: "p1", answers: .blank, notes: nil)
        #expect(!wrote)
        #expect(backend.calls.isEmpty && freshness.homeVersion == 0)
    }
}
