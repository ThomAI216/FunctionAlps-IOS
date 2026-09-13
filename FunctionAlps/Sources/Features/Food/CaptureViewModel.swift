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
        /// The photo flow's mid-flight confirmation: the model was unsure, so the portions are checked ON THIS
        /// SCREEN before the final page (the Expo `PhotoPortionReview`).
        case review(MealLog, PhotoReview.Reason)
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
    /// Post-analysis corrections — exists from the moment the row does.
    private(set) var edit: MealEditModel?
    /// The portion review, while it is up.
    private(set) var review: PhotoReviewModel?
    private var reviewDone = false
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
        edit = MealEditModel(mealId: id, meals: meals, members: members)
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
        case .complete:
            // A complete photo meal the model was unsure about stops here first, once. It waits for `complete`
            // rather than `pricing` so each portion is shown NEXT TO ITS CALORIES.
            if !reviewDone, !request.input.photos.isEmpty, review == nil, let reason = PhotoReview.reason(for: meal), let draft = MealDraft(meal: meal) {
                review = PhotoReviewModel(draft: draft, reason: reason, meals: meals)
                phase = .review(meal, reason)
                return
            }
            edit?.adopt(meal)
            phase = .done(meal)
        case .needsInput, .failed: phase = .attention(meal)
        case .queued, .identifying, .pricing: phase = .working(meal.status)
        }
    }

    /// The member answered the review: their edited, priced meal is what the final page gets — and the row.
    func confirmReview() {
        guard case .review(let meal, _) = phase, let review else { return }
        Task { [weak self] in
            guard let self else { return }
            let draft = await review.confirm()
            if review.changed {
                do { try await meals.updateAnalysis(mealId: meal.id, draft: draft) } catch {
                    Log.data.error("meal.review.persist: \(String(describing: error), privacy: .public)")
                }
            }
            reviewDone = true
            let shown = draft.applied(to: meal)
            latest = shown
            edit?.replace(with: draft)
            self.review = nil
            phase = .done(shown)
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
        edit?.persistOnExit()
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
        case .starting, .stillWorking, .failed, .review: return false
        }
    }

    var isReviewing: Bool { if case .review = phase { return true } else { return false } }

    /// The row as the page renders it: the member's edits folded in.
    var displayed: MealLog? { latest.map { edit?.display($0) ?? $0 } }

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
        case .done, .review: return 4
        case .attention, .stillWorking, .failed: return 3
        }
    }
}
