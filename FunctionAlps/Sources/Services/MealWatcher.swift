import Foundation

/// Live view of one meal row while the pipeline works on it — the Expo `watchMealAnalysis`, transport for
/// transport: read the row at once, open the Realtime channel, and if the channel has not reached
/// `subscribed` within the grace window, poll until it does (or for good, if it never does). A terminal status
/// stops everything. The screen never learns which transport delivered a snapshot; `transport` is there for
/// the day realtime is suspected dead.
@MainActor
final class MealWatcher {
    enum Transport: Sendable { case initial, realtime, polling }

    static let subscribeGrace: Duration = .seconds(4)
    static let pollInterval: Duration = .seconds(3)

    private let meals: MealService
    private let grace: Duration
    private let poll: Duration
    private var subscription: RealtimeSubscription?
    private var graceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var started = false
    private var stopped = false
    private var realtimeLive = false
    private(set) var transport: Transport = .initial
    private(set) var reads = 0

    init(meals: MealService, grace: Duration = MealWatcher.subscribeGrace, poll: Duration = MealWatcher.pollInterval) {
        self.meals = meals
        self.grace = grace
        self.poll = poll
    }

    var isStopped: Bool { stopped }

    /// `onMeal` fires for every snapshot, on the main actor; `onTimeout` once if `maxWait` passes without a
    /// terminal status (the watcher has stopped by then — the server-side worker owns the row).
    func start(id: String, maxWait: Duration? = nil,
               onMeal: @escaping @MainActor @Sendable (MealLog) -> Void,
               onTimeout: (@MainActor @Sendable () -> Void)? = nil) {
        guard !started, !stopped else { return }
        started = true
        let handle: @MainActor @Sendable (MealLog, Transport) -> Void = { [weak self] meal, transport in
            guard let self, !self.stopped else { return }
            self.transport = transport
            onMeal(meal)
            if meal.status.isTerminal { self.stop() }
        }
        Task { await self.read(id, .initial, handle) }
        subscription = meals.subscribe(
            mealId: id,
            onRow: { meal in Task { @MainActor in handle(meal, .realtime) } },
            onLifecycle: { [weak self] status in Task { @MainActor in self?.lifecycle(status, id: id, handle) } }
        )
        graceTask = Task { [weak self, grace] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            self?.startPolling(id, handle)
        }
        if let maxWait {
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: maxWait)
                guard !Task.isCancelled, let self, !self.stopped else { return }
                self.stop()
                onTimeout?()
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        graceTask?.cancel(); graceTask = nil
        pollTask?.cancel(); pollTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        subscription?.cancel(); subscription = nil
    }

    private func read(_ id: String, _ transport: Transport, _ handle: @MainActor @Sendable (MealLog, Transport) -> Void) async {
        guard !stopped else { return }
        reads += 1
        if let meal = try? await meals.meal(id: id) { handle(meal, transport) }
    }

    private func startPolling(_ id: String, _ handle: @escaping @MainActor @Sendable (MealLog, Transport) -> Void) {
        guard !stopped, !realtimeLive, pollTask == nil else { return }
        graceTask?.cancel(); graceTask = nil
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                await self.read(id, .polling, handle)
                try? await Task.sleep(for: self.poll)
            }
        }
    }

    private func lifecycle(_ status: RealtimeLifecycle, id: String, _ handle: @escaping @MainActor @Sendable (MealLog, Transport) -> Void) {
        guard !stopped else { return }
        if status == .subscribed {
            realtimeLive = true
            graceTask?.cancel(); graceTask = nil
            pollTask?.cancel(); pollTask = nil
            // Anything that changed between the initial read and the join landed while no one was listening.
            Task { await self.read(id, .realtime, handle) }
            return
        }
        realtimeLive = false
        startPolling(id, handle)
    }
}
