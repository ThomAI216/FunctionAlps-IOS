import Foundation
import Testing
@testable import FunctionAlps

/// Records every backend call in order so the capture choreography can be asserted.
final class RecordingBackend: FunctionAlpsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    func record(_ call: String) { lock.withLock { _calls.append(call) } }

    var analyzeFailures = 0
    var uploadFails = false
    var storedMeal: MealLog?
    private(set) var lastAnalyze: AnalyzeMealRequest?
    private(set) var lastPending: PendingMealInput?
    private(set) var lastNote: (String, String?)?
    var signCount = 0

    func currentPatientId() async throws -> String? { "p1" }
    func memberProfile(patientId: String) async throws -> MemberProfile? { nil }
    func meals(patientId: String, since: Date) async throws -> [MealLog] { record("meals"); return [] }
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin? { nil }
    func unreadClinicianMessageCount(patientId: String) async throws -> Int { 0 }
    func meal(id: String) async throws -> MealLog? { record("meal"); return storedMeal }
    func createPendingMeal(_ input: PendingMealInput) async throws -> String { record("create"); lastPending = input; return "row-1" }
    func attachMealPhotos(mealId: String, paths: [String]) async throws { record("attach:\(paths.joined(separator: ","))") }
    func analyzeMeal(_ request: AnalyzeMealRequest) async throws {
        record("analyze")
        lastAnalyze = request
        let remaining = lock.withLock { analyzeFailures }
        if remaining > 0 {
            lock.withLock { analyzeFailures -= 1 }
            throw AppError.server(status: 502)
        }
    }
    func updateMealNote(mealId: String, note: String?) async throws { record("note"); lastNote = (mealId, note) }
    func deleteMeal(id: String) async throws { record("delete:\(id)") }
    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String {
        record("upload:\(userId)")
        if uploadFails { throw AppError.server(status: 500) }
        return "\(userId)/\(jpeg.count).jpg"
    }
    func mealPhotoURL(path: String) async throws -> URL { record("sign"); signCount += 1; return URL(string: "https://example.invalid/\(path)?token=t")! }
    func removeMealPhotos(paths: [String]) async throws { record("removePhotos:\(paths.joined(separator: ","))") }
}

@Suite("MealService")
struct MealServiceTests {
    private let noon = Date(timeIntervalSince1970: 1_788_350_400) // 2026-09-02T12:00:00Z
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    private func service(_ backend: RecordingBackend, now: Date? = nil) -> MealService {
        MealService(backend: backend, calendar: utc, now: { now ?? Date() }, retryDelayNanoseconds: 0)
    }

    @Test func photoCaptureIsRowThenPhotoThenModel() async throws {
        let backend = RecordingBackend()
        let jpeg = Data([1, 2, 3])
        let id = try await service(backend).capture(MealCaptureInput(photos: [jpeg], source: .photo), patientId: "p1", userId: "auth-1") { id in
            backend.record("rowCreated:\(id)")
        }
        #expect(id == "row-1")
        #expect(backend.calls == ["create", "rowCreated:row-1", "upload:auth-1", "attach:auth-1/3.jpg", "analyze"])
        let analyze = try #require(backend.lastAnalyze)
        #expect(analyze.mealId == "row-1")
        #expect(analyze.imageBase64s == [jpeg.base64EncodedString()])
        #expect(analyze.description == nil)
        let pending = try #require(backend.lastPending)
        #expect(pending.source == .photo)
        #expect(pending.description == nil)
        #expect(pending.patientId == "p1")
    }

    @Test func textCaptureSkipsStorageAndRetriesThreeTimes() async throws {
        let backend = RecordingBackend()
        backend.analyzeFailures = 5
        _ = try await service(backend).capture(MealCaptureInput(description: " oats and berries ", source: .text), patientId: "p1", userId: "auth-1")
        #expect(backend.calls == ["create", "analyze", "analyze", "analyze"])
        #expect(backend.lastAnalyze?.description == "oats and berries")
        #expect(backend.lastPending?.description == "oats and berries")
    }

    @Test func photoCaptureCallsTheModelOnceEvenOnFailure() async throws {
        let backend = RecordingBackend()
        backend.analyzeFailures = 5
        _ = try await service(backend).capture(MealCaptureInput(photos: [Data([9])], source: .photo), patientId: "p1", userId: "u")
        #expect(backend.calls.filter { $0 == "analyze" }.count == 1)
    }

    @Test func failedUploadStillAnalysesFromBytes() async throws {
        let backend = RecordingBackend()
        backend.uploadFails = true
        _ = try await service(backend).capture(MealCaptureInput(photos: [Data([9])], source: .photo), patientId: "p1", userId: "u")
        #expect(backend.calls == ["create", "upload:u", "analyze"])
        #expect(backend.lastAnalyze?.imageBase64s.count == 1)
    }

    @Test func mealTypeFollowsTheClock() {
        func at(_ hour: Int) -> MealLog.MealType {
            var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 3; comps.hour = hour
            return MealService.mealType(at: utc.date(from: comps)!, calendar: utc)
        }
        #expect(at(7) == .breakfast)
        #expect(at(10) == .breakfast)
        #expect(at(11) == .lunch)
        #expect(at(14) == .lunch)
        #expect(at(16) == .snack)
        #expect(at(19) == .dinner)
        #expect(at(23) == .dinner)
    }

    @Test func pendingRowUsesTheServiceClockAndSlot() async throws {
        let backend = RecordingBackend()
        _ = try await service(backend, now: noon).capture(MealCaptureInput(description: "x", source: .voice), patientId: "p1", userId: "u")
        #expect(backend.lastPending?.mealType == .lunch)
        #expect(backend.lastPending?.loggedAt == noon)
        #expect(backend.lastPending?.source == .voice)
    }

    @Test func reanalyzePhotoMealReadsFromStorage() async throws {
        let backend = RecordingBackend()
        let meal = MealLog(id: "m1", loggedAt: Date(), name: "Bowl", photoPaths: ["u/1.jpg"])
        await service(backend).reanalyze(meal, description: "")
        let request = try #require(backend.lastAnalyze)
        #expect(request.reanalyze)
        #expect(request.imageBase64s.isEmpty)
        #expect(request.description == nil)
    }

    @Test func reanalyzeTextMealFallsBackToStoredName() async throws {
        let backend = RecordingBackend()
        backend.analyzeFailures = 1
        let meal = MealLog(id: "m1", loggedAt: Date(), name: "oats", source: .text)
        await service(backend).reanalyze(meal, description: nil)
        #expect(backend.lastAnalyze?.description == "oats")
        #expect(backend.calls.filter { $0 == "analyze" }.count == 2)
    }

    @Test func normalizesNotesLikeTheDatabaseCheck() {
        #expect(MealService.normalizeNote(nil) == nil)
        #expect(MealService.normalizeNote("   ") == nil)
        #expect(MealService.normalizeNote("  hi  ") == "hi")
        let long = String(repeating: "a", count: 2500)
        #expect(MealService.normalizeNote(long)?.count == 2000)
    }

    @Test func noteUpdateSendsNormalisedValue() async throws {
        let backend = RecordingBackend()
        try await service(backend).updateNote(mealId: "m1", note: "  ")
        #expect(backend.lastNote?.1 == nil)
    }

    @Test func deleteRemovesPhotosFirst() async throws {
        let backend = RecordingBackend()
        try await service(backend).delete(MealLog(id: "m1", loggedAt: Date(), photoPaths: ["u/1.jpg", "u/2.jpg"]))
        #expect(backend.calls == ["removePhotos:u/1.jpg,u/2.jpg", "delete:m1"])
    }

    @Test func signedURLsAreCached() async throws {
        let backend = RecordingBackend()
        let s = service(backend, now: noon)
        _ = try await s.photoURL(path: "u/1.jpg")
        _ = try await s.photoURL(path: "u/1.jpg")
        _ = try await s.photoURL(path: "u/2.jpg")
        #expect(backend.signCount == 2)
    }

    @Test func recentMealsCoverThirtyDays() async throws {
        let backend = RecordingBackend()
        _ = try await service(backend).recentMeals(patientId: "p1")
        #expect(backend.calls == ["meals"])
    }
}

@Suite("MealPhotoRef")
struct MealPhotoRefTests {
    @Test func resolvesEveryStoredShape() {
        #expect(MealPhotoRef.storagePath("uid/1.jpg") == "uid/1.jpg")
        #expect(MealPhotoRef.storagePath("/uid/1.jpg") == "uid/1.jpg")
        #expect(MealPhotoRef.storagePath("https://x.supabase.co/storage/v1/object/public/meal-images/uid/1.jpg") == "uid/1.jpg")
        #expect(MealPhotoRef.storagePath("https://x.supabase.co/storage/v1/object/sign/meal-images/uid/1.jpg?token=abc") == "uid/1.jpg")
        #expect(MealPhotoRef.storagePath("https://elsewhere.example/photo.jpg") == nil)
        #expect(MealPhotoRef.storagePath("   ") == nil)
        #expect(MealPhotoRef.storagePath(nil) == nil)
    }

    @Test func photoUrlsWinAndAreNeverConcatenated() {
        #expect(MealPhotoRef.paths(photoUrl: "a.jpg", photoUrls: ["a.jpg", "b.jpg"]) == ["a.jpg", "b.jpg"])
        #expect(MealPhotoRef.paths(photoUrl: "a.jpg", photoUrls: []) == ["a.jpg"])
        #expect(MealPhotoRef.paths(photoUrl: nil, photoUrls: nil) == [])
    }
}

@Suite("MealLog status")
struct MealLogStatusTests {
    @Test func absentStatusMeansComplete() {
        let meal = MealLog(id: "1", loggedAt: Date())
        #expect(meal.status == .complete)
        #expect(meal.isAnalysed)
    }

    @Test func terminalStates() {
        #expect(MealLog.AnalysisStatus.complete.isTerminal)
        #expect(MealLog.AnalysisStatus.needsInput.isTerminal)
        #expect(MealLog.AnalysisStatus.failed.isTerminal)
        #expect(!MealLog.AnalysisStatus.queued.isTerminal)
        #expect(!MealLog.AnalysisStatus.identifying.isTerminal)
        #expect(!MealLog.AnalysisStatus.pricing.isTerminal)
        #expect(MealLog.AnalysisStatus(rawValue: "needs_input") == .needsInput)
    }
}
