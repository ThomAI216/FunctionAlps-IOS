import Foundation
import Observation

/// Drives one capture: create → upload → analyse, while WATCHING the row (polling; Supabase
/// Realtime is a later step). The screen renders the row's truth, never the client's guess.
@MainActor
@Observable
final class CaptureViewModel {
    enum Phase: Equatable {
        case starting
        case working(MealLog.AnalysisStatus)
        case done(MealLog)
        /// `needs_input` or `failed`: the member can add words and try again, or keep the row.
        case attention(MealLog)
        /// The interactive window closed; the server-side worker finishes the row later.
        case stillWorking
        case failed(AppError)
    }

    static let pollInterval: Duration = .seconds(3)
    static let maxWait: Duration = .seconds(150)

    let request: CaptureRequest
    var phase: Phase = .starting
    /// The "tell us what you ate" card's machine — the SAME one the Food tab's describe card runs.
    let describe: MealDictationModel
    private(set) var submitting = false
    var submitError: String?
    private(set) var mealId: String?
    /// The row as last read — the screen renders the row's truth, never the client's guess.
    private(set) var latest: MealLog?

    private let meals: MealService
    private let members: MemberService
    private var captureTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    init(request: CaptureRequest, meals: MealService, members: MemberService) {
        self.request = request
        self.meals = meals
        self.members = members
        describe = MealDictationModel(meals: meals) { [input = request.input] in input.mealType }
    }

    func start() {
        guard captureTask == nil else { return }
        phase = .starting
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let member = try await members.currentMember()
                _ = try await meals.capture(request.input, patientId: member.patientId, userId: member.userId) { id in
                    await self.rowCreated(id)
                }
            } catch let error as AppError {
                Log.error(error, in: Log.data, context: "capture.start")
                if mealId == nil { phase = .failed(error) }
            } catch {
                Log.data.error("capture.start: \(String(describing: error), privacy: .public)")
                if mealId == nil { phase = .failed(.unknown(detail: String(describing: error))) }
            }
            captureTask = nil
        }
    }

    /// After a hard failure before the row existed.
    func restart() {
        captureTask?.cancel()
        captureTask = nil
        start()
    }

    private func rowCreated(_ id: String) {
        mealId = id
        phase = .working(.queued)
        watch(id)
    }

    private func watch(_ id: String) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            let started = ContinuousClock.now
            while !Task.isCancelled {
                guard let self else { return }
                if let meal = try? await meals.meal(id: id) {
                    apply(meal)
                    if meal.status.isTerminal { return }
                }
                if ContinuousClock.now - started > Self.maxWait {
                    phase = .stillWorking
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func apply(_ meal: MealLog) {
        latest = meal
        switch meal.status {
        case .complete: phase = .done(meal)
        case .needsInput, .failed: phase = .attention(meal)
        case .queued, .identifying, .pricing: phase = .working(meal.status)
        }
    }

    /// The member answered the needs_input question. The row is re-identified from their words + structured
    /// portions; the watcher restarts because needs_input was terminal.
    func submitDescription() {
        guard case .attention(let meal) = phase, describe.canAnalyse, !submitting else { return }
        let words = describe.confirmedDescription()
        let items = describe.confirmedItems()
        guard !words.isEmpty || !items.isEmpty else { return }
        submitting = true
        submitError = nil
        Task { [weak self] in
            guard let self else { return }
            await meals.describe(meal, description: words, items: items)
            submitting = false
            describe.reset()
            phase = .working(.queued)
            watch(meal.id)
        }
    }

    /// "Or try the photo again": the server re-reads the stored photos and starts the attempt budget again.
    func retryPhoto() {
        guard case .attention(let meal) = phase, !meal.photoPaths.isEmpty else { return }
        phase = .working(.queued)
        Task { [weak self] in
            guard let self else { return }
            await meals.reanalyze(meal, description: nil)
        }
        watch(meal.id)
    }

    func cancel() {
        captureTask?.cancel()
        watchTask?.cancel()
    }

    var status: MealLog.AnalysisStatus? {
        if case .working(let s) = phase { return s }
        return latest?.status
    }

    /// The early hand-off: the member sees their identified food while the numbers are still being
    /// looked up (`pricing`), and every terminal state lands on the meal page too.
    var showsResult: Bool {
        switch phase {
        case .done, .attention: return true
        case .working(let s): return s == .pricing && !(latest?.items.isEmpty ?? true)
        case .starting, .stillWorking, .failed: return false
        }
    }

    var stepIndex: Int {
        switch phase {
        case .starting: return 0
        case .working(let status):
            switch status {
            case .queued: return 1
            case .identifying: return 2
            case .pricing: return 3
            default: return 3
            }
        case .done: return 4
        case .attention, .stillWorking, .failed: return 3
        }
    }
}
