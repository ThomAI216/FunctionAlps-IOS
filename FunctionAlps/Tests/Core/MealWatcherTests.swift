import Foundation
import Testing
@testable import FunctionAlps

/// The read → subscribe → grace → poll choreography, with a fake channel. Timings are shrunk; the assertions
/// are about ORDER and about which transport is running, not about wall-clock.
@MainActor
struct MealWatcherTests {
    private func meal(_ status: MealLog.AnalysisStatus) -> MealLog {
        MealLog(id: "m1", loggedAt: Date(), name: "Bowl", analysisStatus: status)
    }

    private func sleep(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    @Test func noRealtimeFallsBackToPollingAfterTheGrace() async {
        let backend = RecordingBackend()
        backend.storedMeal = meal(.identifying)
        let watcher = MealWatcher(meals: MealService(backend: backend), grace: .milliseconds(40), poll: .milliseconds(30))
        let seen = StatusLog()
        watcher.start(id: "m1") { seen.append($0.status) }
        await sleep(20)
        #expect(watcher.reads == 1)                 // the initial read only, inside the grace
        await sleep(200)
        #expect(watcher.reads >= 3)                 // polling engaged
        #expect(watcher.transport == .polling)
        #expect(!seen.values.isEmpty && seen.values.allSatisfy { $0 == .identifying })
        #expect(!watcher.isStopped)
        watcher.stop()
    }

    @Test func aSubscribedChannelStopsThePollAndReadsOnce() async {
        let backend = RecordingBackend()
        backend.storedMeal = meal(.identifying)
        backend.subscribeHook = { _, _, lifecycle in
            lifecycle(.subscribed)
            return .inert
        }
        let watcher = MealWatcher(meals: MealService(backend: backend), grace: .milliseconds(40), poll: .milliseconds(30))
        watcher.start(id: "m1") { _ in }
        await sleep(250)
        #expect(watcher.reads == 2)                 // initial + the post-join catch-up, and nothing else
        #expect(watcher.transport == .realtime)
        watcher.stop()
    }

    @Test func aRealtimeRowIsDeliveredAndATerminalOneStopsEverything() async {
        let backend = RecordingBackend()
        backend.storedMeal = meal(.pricing)
        let cancelled = Cancelled()
        let box = RowBox()
        backend.subscribeHook = { _, onRow, lifecycle in
            box.onRow = onRow
            lifecycle(.subscribed)
            return RealtimeSubscription { cancelled.flag() }
        }
        let watcher = MealWatcher(meals: MealService(backend: backend), grace: .milliseconds(40), poll: .milliseconds(30))
        let seen = StatusLog()
        watcher.start(id: "m1") { seen.append($0.status) }
        await sleep(60)
        box.onRow?(meal(.complete))
        await sleep(60)
        #expect(seen.values.last == .complete)
        #expect(watcher.isStopped)
        #expect(cancelled.value)
    }

    @Test func aChannelErrorFallsBackToPolling() async {
        let backend = RecordingBackend()
        backend.storedMeal = meal(.identifying)
        backend.subscribeHook = { _, _, lifecycle in
            lifecycle(.channelError)
            return .inert
        }
        let watcher = MealWatcher(meals: MealService(backend: backend), grace: .seconds(10), poll: .milliseconds(30))
        watcher.start(id: "m1") { _ in }
        await sleep(150)
        #expect(watcher.reads >= 3)
        #expect(watcher.transport == .polling)
        watcher.stop()
    }

    @Test func maxWaitStopsAndReportsOnce() async {
        let backend = RecordingBackend()
        backend.storedMeal = meal(.queued)
        let watcher = MealWatcher(meals: MealService(backend: backend), grace: .seconds(10), poll: .seconds(10))
        let timeouts = Counter()
        watcher.start(id: "m1", maxWait: .milliseconds(50), onMeal: { _ in }, onTimeout: { timeouts.bump() })
        await sleep(150)
        #expect(watcher.isStopped)
        #expect(timeouts.value == 1)
    }
}

private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _v: [MealLog.AnalysisStatus] = []
    var values: [MealLog.AnalysisStatus] { lock.withLock { _v } }
    func append(_ s: MealLog.AnalysisStatus) { lock.withLock { _v.append(s) } }
}

private final class Cancelled: @unchecked Sendable {
    private let lock = NSLock()
    private var _v = false
    var value: Bool { lock.withLock { _v } }
    func flag() { lock.withLock { _v = true } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _v = 0
    var value: Int { lock.withLock { _v } }
    func bump() { lock.withLock { _v += 1 } }
}

private final class RowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _onRow: (@Sendable (MealLog) -> Void)?
    var onRow: (@Sendable (MealLog) -> Void)? {
        get { lock.withLock { _onRow } }
        set { lock.withLock { _onRow = newValue } }
    }
}

struct PhotoGroupingTests {
    @Test func oneOrNoneNeverAsks() {
        #expect(MealPhotoGrouping.choice(for: 0) == .single)
        #expect(MealPhotoGrouping.choice(for: 1) == .single)
        #expect(MealPhotoGrouping.choice(for: 2) == .ask)
    }

    @Test func oneMealIsOfferedUpToTheModelsCapOnly() {
        #expect(!MealPhotoGrouping.oneMealAllowed(1))
        #expect(MealPhotoGrouping.oneMealAllowed(2))
        #expect(MealPhotoGrouping.oneMealAllowed(MealPhotoGrouping.maxPerMeal))
        #expect(!MealPhotoGrouping.oneMealAllowed(MealPhotoGrouping.maxPerMeal + 1))
    }

    @Test func theQueueAdvancesInOrderAndCountsFromOne() {
        var r = CaptureRequest(input: MealCaptureInput(photos: [Data([1])], source: .photo))
        r.queue = [Data([2]), Data([3])]
        r.total = 3
        #expect(r.nextPosition == 2)
        let second = r.advanced()
        #expect(second?.input.photos == [Data([2])])
        #expect(second?.nextPosition == 3)
        let third = second?.advanced()
        #expect(third?.input.photos == [Data([3])])
        #expect(third?.nextPosition == nil)
        #expect(third?.advanced() == nil)
    }
}

struct SnakeKeysTests {
    @Test func camelKeysComeBackAsColumns() {
        #expect(SnakeKeys.snake("vitaminCMg") == "vitamin_c_mg")
        #expect(SnakeKeys.snake("saturatedFatG") == "saturated_fat_g")
        #expect(SnakeKeys.snake("omega3G") == "omega3_g")
        #expect(SnakeKeys.snake("vitaminB12Mcg") == "vitamin_b12_mcg")
        #expect(SnakeKeys.snake("iron_mg") == "iron_mg")
    }

    @Test func aWholeMapIsRekeyed() {
        #expect(SnakeKeys.normalise(["vitaminCMg": 1, "iron_mg": 2]) == ["vitamin_c_mg": 1, "iron_mg": 2])
    }
}
