import Foundation
import Observation

/// One capture, presented full-screen until the meal is read (or handed to the server).
struct CaptureRequest: Identifiable, Sendable {
    let id = UUID()
    let input: MealCaptureInput
}

@MainActor
@Observable
final class FoodViewModel {
    struct Content: Sendable, Equatable {
        let member: Member
        let meals: [MealLog]
    }

    /// The re-log toast: the row is already inserted; Undo deletes it again, Adjust opens it.
    struct RelogToast: Equatable {
        let mealId: String
        let name: String
        let kcal: Double?
    }

    var state: Loadable<Content> = .loading
    var description = ""
    private(set) var isRefreshing = false
    private(set) var favorites: [FavoriteMeal] = []
    private(set) var reactions: [String: MealReaction] = [:]
    /// A meal was inserted by re-log — the notification engine schedules its 2.5 h follow-up.
    @ObservationIgnored var onMealLogged: (@MainActor (String) -> Void)?
    var relogToast: RelogToast?
    var errorMessage: String?
    let dictation: SpeechDictation
    /// The last words in the field came from the microphone (the capture's `source`).
    private var spoke = false
    /// What `preprocess-meal` made of the words — kept visible while the next extraction runs.
    private(set) var extracted: MealPreprocess?
    private(set) var extracting = false
    private var lastExtracted = ""
    private var extractTask: Task<Void, Never>?
    private var pendingExtract: String?
    /// The Expo `LIVE_EXTRACT_DEBOUNCE_MS`.
    static let extractDebounceMs = 700

    private let members: MemberService
    private let meals: MealService
    private let auth: AuthService
    private let calendar: Calendar
    private var toastTask: Task<Void, Never>?

    init(members: MemberService, meals: MealService, auth: AuthService, calendar: Calendar = .current) {
        self.members = members
        self.meals = meals
        self.auth = auth
        self.calendar = calendar
        dictation = SpeechDictation { audio, mime in try await meals.transcribe(audio: audio, mimeType: mime) }
        dictation.onFinal = { [weak self] words in
            guard let self else { return }
            let current = self.description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.description = current.isEmpty ? words : current + " " + words
            self.spoke = true
            self.descriptionChanged()
        }
    }

    func load(refresh: Bool = false) async {
        if refresh { isRefreshing = true } else if state.value == nil { state = .loading }
        defer { isRefreshing = false }
        do {
            let member = try await members.currentMember()
            async let recent = meals.recentMeals(patientId: member.patientId)
            async let favs = meals.favorites(patientId: member.patientId)
            async let felt = meals.reactions(patientId: member.patientId)
            state = .loaded(Content(member: member, meals: try await recent))
            favorites = await favs
            reactions = await felt
        } catch MemberService.MemberError.notRegistered {
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "food.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            Log.data.error("food.load: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    // MARK: Capture entry points

    var canDescribe: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Wire to the field: every edit re-extracts after the debounce (typing produces one per keystroke).
    func descriptionChanged() {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { extracted = nil; lastExtracted = ""; extractTask?.cancel(); extractTask = nil; return }
        extractTask?.cancel()
        extractTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.extractDebounceMs))
            guard !Task.isCancelled else { return }
            await self?.extract(text)
        }
    }

    /// Debounce + coalesce + one in flight: only the newest pending text survives a running extraction.
    private func extract(_ text: String) async {
        guard text.count >= 3, text != lastExtracted else { return }
        if extracting { pendingExtract = text; return }
        extracting = true
        lastExtracted = text
        do {
            extracted = try await meals.preprocess(text, mealType: nil)
        } catch {
            Log.data.error("food.preprocess: \(String(describing: error), privacy: .public)")
        }
        extracting = false
        if let queued = pendingExtract { pendingExtract = nil; await extract(queued) }
    }

    /// The typed/spoken meal split into ingredient lines — the fallback while nothing is extracted yet.
    var describedItems: [String] {
        description
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " et ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Hands the typed meal to the capture flow and clears the field.
    func takeTextCapture() -> MealCaptureInput? {
        guard canDescribe else { return nil }
        var input = MealCaptureInput(description: description, source: spoke ? .voice : .text)
        // The structured list only when it was made from THESE words — a stale list would price the wrong meal.
        if let extracted, lastExtracted == description.trimmingCharacters(in: .whitespacesAndNewlines) {
            input.statedItems = extracted.items.compactMap(\.stated)
        }
        description = ""
        spoke = false
        extracted = nil
        lastExtracted = ""
        extractTask?.cancel()
        return input
    }

    func captureFinished() {
        Task { await load(refresh: true) }
    }

    // MARK: Favorites + re-log

    func isFavorite(_ meal: MealLog) -> Bool { favorites.contains { $0.sourceMealLogId == meal.id } }

    func toggleFavorite(_ meal: MealLog) {
        guard let member = state.value?.member else { return }
        Task {
            do {
                if let existing = favorites.first(where: { $0.sourceMealLogId == meal.id }) {
                    try await meals.removeFavorite(id: existing.id)
                    favorites.removeAll { $0.id == existing.id }
                } else {
                    let fav = try await meals.addFavorite(meal, patientId: member.patientId)
                    favorites.insert(fav, at: 0)
                }
            } catch let error as AppError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    /// Log again: the row is inserted immediately; the toast offers Undo (deletes it) and Adjust.
    func relog(_ source: RelogSource, favoriteId: String? = nil) {
        guard let member = state.value?.member else { return }
        Task {
            do {
                let id = try await meals.relog(source, patientId: member.patientId, favoriteId: favoriteId)
                showToast(RelogToast(mealId: id, name: source.name, kcal: source.kcal))
                onMealLogged?(id)
                await load(refresh: true)
            } catch let error as AppError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    func undoRelog() {
        guard let toast = relogToast else { return }
        toastTask?.cancel()
        relogToast = nil
        Task {
            await meals.deleteRelogged(id: toast.mealId)
            await load(refresh: true)
        }
    }

    /// Returns the meal to open on "Adjust" and dismisses the toast.
    func adjustRelog() -> String? {
        guard let toast = relogToast else { return nil }
        toastTask?.cancel()
        relogToast = nil
        return toast.mealId
    }

    private func showToast(_ toast: RelogToast) {
        toastTask?.cancel()
        relogToast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.relogToast = nil
        }
    }

    // MARK: Derived

    func todayMeals(_ content: Content) -> [MealLog] {
        content.meals.filter { calendar.isDateInToday($0.loggedAt) }
    }

    /// Newest first — the Food tab's single list (no day labels, the Expo card carries the date).
    func recentMeals(_ content: Content) -> [MealLog] {
        content.meals.sorted { $0.loggedAt > $1.loggedAt }
    }

    /// 14-day micronutrient coverage per day (oldest first), nil where no meal carries micros.
    func microTrend(_ content: Content) -> [Int?] {
        let sex = content.member.profile?.sex
        return (0..<14).reversed().map { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { return nil }
            let dayMeals = content.meals.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            return MicroCoverage.overall(meals: dayMeals, sex: sex)
        }
    }

    /// Today's mean of the three food scores over the scored meals.
    func todayScores(_ content: Content) -> MealScores? {
        let scored = todayMeals(content).compactMap(\.scores)
        guard !scored.isEmpty else { return nil }
        let n = Double(scored.count)
        return MealScores(
            inflammation: Int((scored.map { Double($0.inflammation) }.reduce(0, +) / n).rounded()),
            glycemic: Int((scored.map { Double($0.glycemic) }.reduce(0, +) / n).rounded()),
            digestion: Int((scored.map { Double($0.digestion) }.reduce(0, +) / n).rounded())
        )
    }

    /// "today · 14:05", "yesterday · 20:10", "28.08 · 12:30" — the Expo `formatWhen`.
    func when(_ date: Date) -> String {
        let hm = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDateInToday(date) { return String(localized: "food.when.today", defaultValue: "today · \(hm)") }
        if calendar.isDateInYesterday(date) { return String(localized: "food.when.yesterday", defaultValue: "yesterday · \(hm)") }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)) + " · " + hm
    }
}
