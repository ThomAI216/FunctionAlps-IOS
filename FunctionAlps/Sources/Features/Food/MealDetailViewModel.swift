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
    private(set) var reaction: MealReaction?
    /// Corrections, days later — the same editor as the capture page.
    let edit: MealEditModel

    private let mealId: String
    private let meals: MealService
    private let auth: AuthService
    private var watcher: MealWatcher?

    init(mealId: String, meals: MealService, members: MemberService, auth: AuthService) {
        self.mealId = mealId
        self.meals = meals
        self.auth = auth
        edit = MealEditModel(mealId: mealId, meals: meals, members: members)
    }

    func load() async {
        do {
            guard let meal = try await meals.meal(id: mealId) else {
                state = .empty
                return
            }
            state = .loaded(meal)
            edit.adopt(meal)
            noteDraft = meal.patientNote ?? ""
            reaction = await meals.reaction(mealId: mealId)
            if meal.status.isWorking { watch() }
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "meal.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    /// A meal still being analysed keeps refreshing until it settles (Realtime, polling underneath).
    private func watch() {
        if let watcher, !watcher.isStopped { return }
        let w = MealWatcher(meals: meals)
        watcher = w
        w.start(id: mealId, maxWait: .seconds(150)) { [weak self] meal in
            guard let self else { return }
            state = .loaded(meal)
            edit.adopt(meal)
        }
    }

    /// The reaction sheet saved a row: show it without a reload.
    func reactionSaved(_ r: MealReaction) { reaction = r }

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

    func cancel() { edit.persistOnExit(); watcher?.stop(); watcher = nil }
}
