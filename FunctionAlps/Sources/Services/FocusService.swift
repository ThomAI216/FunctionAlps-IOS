import Foundation
import Observation

/// Today's focus as one shared, observable value: the check-in screen asks for a recomputation, the Home card
/// shows the result, and neither needs to know about the other.
///
/// Loads are SERIALISED. Saving the morning check-in recomputes the day while returning to Home asks for it
/// again; if the plain read landed last it would put the pre-edit day back on screen. So a read waits for any
/// load already in flight, and a recomputation queues behind it rather than racing.
@MainActor
@Observable
final class FocusService {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(TodayFocus)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private var inflight: Task<Void, Never>?
    private var generation = 0

    init(backend: any FunctionAlpsBackend, auth: AuthService) {
        self.backend = backend
        self.auth = auth
    }

    var focus: TodayFocus? {
        if case .loaded(let f) = phase { return f }
        return nil
    }

    /// Reads today's focus (computing it the first time the morning allows). `recompute` after the morning
    /// check-in is saved or edited, so a changed morning retires what no longer fits.
    func load(recompute: Bool = false) async {
        if let running = inflight, !recompute { await running.value; return }
        let previous = inflight
        generation += 1
        let mine = generation
        let task = Task { [weak self] in
            await previous?.value
            await self?.fetch(recompute: recompute)
        }
        inflight = task
        await task.value
        if generation == mine { inflight = nil }
    }

    private func fetch(recompute: Bool) async {
        // Keep what is on screen while refreshing; only a first load shows the spinner.
        if focus == nil { phase = .loading }
        do {
            phase = .loaded(try await backend.dailyFocus(recompute: recompute))
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "focus.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if focus == nil { phase = .failed(error.userMessage) }
        } catch {
            if focus == nil { phase = .failed(String(describing: error)) }
        }
    }

    /// Done, or undone. Shown at once and written behind; a failed write puts it back as it was.
    func setCompleted(_ offer: FocusOffer, _ completed: Bool) async {
        guard case .loaded(let current) = phase, let i = current.offers.firstIndex(where: { $0.id == offer.id }) else { return }
        var offers = current.offers
        offers[i].completed = completed
        if completed { offers[i].accepted = true }
        phase = .loaded(TodayFocus(day: current.day, needsCheckin: current.needsCheckin, offers: offers))
        do {
            try await backend.setFocusOfferCompleted(id: offer.id, completed: completed)
        } catch {
            if case .loaded(let now) = phase, let j = now.offers.firstIndex(where: { $0.id == offer.id }) {
                var back = now.offers
                back[j] = offer
                phase = .loaded(TodayFocus(day: now.day, needsCheckin: now.needsCheckin, offers: back))
            }
            if let appError = error as? AppError {
                Log.error(appError, in: Log.data, context: "focus.done")
                if case .unauthorized = appError { await auth.handleUnauthorized() }
            }
        }
    }
}
