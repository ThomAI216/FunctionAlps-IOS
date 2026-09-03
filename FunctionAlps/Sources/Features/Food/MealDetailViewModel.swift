import Foundation
import Observation

@MainActor
@Observable
final class MealDetailViewModel {
    var state: Loadable<MealLog> = .loading
    var noteDraft = ""
    var isSavingNote = false
    var isDeleting = false
    var errorMessage: String?

    private let mealId: String
    private let meals: MealService
    private let auth: AuthService
    private var watchTask: Task<Void, Never>?

    init(mealId: String, meals: MealService, auth: AuthService) {
        self.mealId = mealId
        self.meals = meals
        self.auth = auth
    }

    func load() async {
        do {
            guard let meal = try await meals.meal(id: mealId) else {
                state = .empty
                return
            }
            state = .loaded(meal)
            noteDraft = meal.patientNote ?? ""
            if meal.status.isWorking { watch() }
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "meal.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    /// A meal still being analysed keeps refreshing until it settles.
    private func watch() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            for _ in 0..<50 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if let meal = try? await meals.meal(id: mealId) {
                    state = .loaded(meal)
                    if meal.status.isTerminal { break }
                }
            }
            self?.watchTask = nil
        }
    }

    func saveNote() async -> Bool {
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            try await meals.updateNote(mealId: mealId, note: noteDraft)
            await load()
            return true
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(describing: error)
        }
        return false
    }

    func delete() async -> Bool {
        guard let meal = state.value else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await meals.delete(meal)
            return true
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(describing: error)
        }
        return false
    }

    func cancel() { watchTask?.cancel(); watchTask = nil }
}
