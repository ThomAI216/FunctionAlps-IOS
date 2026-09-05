import Foundation

/// What the member hands over at capture time: JPEG bytes and/or their words.
struct MealCaptureInput: Sendable, Equatable {
    var photos: [Data] = []
    var description: String? = nil
    /// The extracted list (`preprocess-meal`) travelling with the words — grams as fields.
    var statedItems: [StatedItem] = []
    let source: MealLog.Source
    var mealType: MealLog.MealType? = nil

    var trimmedDescription: String? {
        let words = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return words.isEmpty ? nil : words
    }
    var isEmpty: Bool { photos.isEmpty && trimmedDescription == nil }
}

/// The meal loop, mirroring the Expo app's async capture (lib/meal-log/async-capture.ts):
/// row → photo → model. The ORDER is the design — the row exists before the slow parts, so a
/// force-quit one second after the shutter still leaves a meal the server can finish.
struct MealService: Sendable {
    static let historyDays = 30
    /// The server hedges photo analysis itself and a worker retries from storage: one client call.
    static let photoAttempts = 1
    /// A text meal's first identification has nothing server-side to retry from: three client calls.
    static let textAttempts = 3
    static let signedURLTTL: TimeInterval = 3600
    static let noteMaxLength = 2000

    private let backend: any FunctionAlpsBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let retryDelayNanoseconds: UInt64
    private let photoURLs = PhotoURLCache()

    init(backend: any FunctionAlpsBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }, retryDelayNanoseconds: UInt64 = 600_000_000) {
        self.backend = backend
        self.calendar = calendar
        self.now = now
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    /// "Say or type your meal, watch the ingredients appear": the words → the structured list.
    func preprocess(_ transcript: String, mealType: MealLog.MealType?) async throws -> MealPreprocess {
        try await backend.preprocessMeal(transcript: transcript, mealType: mealType?.rawValue, locale: ConsentLogic.locale())
    }

    /// "Describe by voice": the recording goes to the sovereign Whisper; the words come back as if typed.
    func transcribe(audio: Data, mimeType: String) async throws -> String {
        try await backend.transcribeAudio(base64: audio.base64EncodedString(), mimeType: mimeType)
    }

    // MARK: Reads

    func recentMeals(patientId: String) async throws -> [MealLog] {
        let since = calendar.date(byAdding: .day, value: -Self.historyDays, to: now()) ?? now()
        return try await backend.meals(patientId: patientId, since: since)
    }

    func meal(id: String) async throws -> MealLog? {
        try await backend.meal(id: id)
    }

    /// How the meal felt afterwards, when the member rated it (`nb_meal_reactions`).
    func reaction(mealId: String) async -> MealReaction? {
        try? await backend.mealReaction(mealId: mealId)
    }

    /// Reactions for the 30-day list, keyed by meal id. Best effort — a failed read leaves the lines unrated.
    func reactions(patientId: String) async -> [String: MealReaction] {
        let since = calendar.date(byAdding: .day, value: -Self.historyDays, to: now()) ?? now()
        return (try? await backend.mealReactions(patientId: patientId, since: since)) ?? [:]
    }

    /// The member rated the meal (the reaction sheet, or "Felt fine" from the notification). Symptoms 0–10.
    func saveReaction(mealId: String, patientId: String, overall: Double?, bloating: Int = 0, fullness: Int = 0, gas: Int = 0, flags: [String] = [], responses: [String: Double]? = nil) async throws {
        try await backend.saveMealReaction(MealReactionWrite(
            patientId: patientId, mealLogId: mealId, overall: overall, bloating: bloating, fullness: fullness, gasBurden: gas,
            responses: responses, reactionFlags: flags.isEmpty ? nil : flags, reactionTime: ISO8601.string(now())
        ))
    }

    // MARK: Favorites + re-log

    func favorites(patientId: String) async -> [FavoriteMeal] {
        (try? await backend.favorites(patientId: patientId)) ?? []
    }

    func addFavorite(_ meal: MealLog, patientId: String) async throws -> FavoriteMeal {
        try await backend.addFavorite(meal, patientId: patientId)
    }

    func removeFavorite(id: String) async throws {
        try await backend.removeFavorite(id: id)
    }

    /// The INVERSE of delete's undo: the row is inserted immediately (the meal is real the moment the
    /// toast appears) and Undo deletes it again. Returns the new row id.
    func relog(_ source: RelogSource, patientId: String, favoriteId: String? = nil) async throws -> String {
        let id = try await backend.relogMeal(source, patientId: patientId)
        if let favoriteId { try? await backend.touchFavorite(id: favoriteId) }
        return id
    }

    func deleteRelogged(id: String) async {
        try? await backend.deleteMeal(id: id)
    }

    // MARK: Capture

    /// Returns the row id once the interactive analysis call has settled. `onRowCreated` fires the
    /// moment the row exists (before uploads) so a screen can start watching it at ~1 s.
    /// A failed or hung analysis call is NOT an error here: the row is queued and the server-side
    /// worker owns it from then on.
    func capture(_ input: MealCaptureInput, patientId: String, userId: String, onRowCreated: @Sendable (String) async -> Void = { _ in }) async throws -> String {
        let words = input.trimmedDescription
        let mealId = try await backend.createPendingMeal(PendingMealInput(
            patientId: patientId,
            mealType: input.mealType ?? Self.mealType(at: now(), calendar: calendar),
            source: input.source,
            description: words,
            loggedAt: now()
        ))
        await onRowCreated(mealId)

        // Sequential on purpose: hundreds of KB each on a phone connection.
        var uploaded: [String] = []
        for photo in input.photos {
            do {
                uploaded.append(try await backend.uploadMealPhoto(userId: userId, jpeg: photo))
            } catch {
                Log.data.error("meal.upload: \(String(describing: error), privacy: .public)")
            }
        }
        if !uploaded.isEmpty {
            do { try await backend.attachMealPhotos(mealId: mealId, paths: uploaded) } catch {
                Log.data.error("meal.attach: \(String(describing: error), privacy: .public)")
            }
        }

        var request = AnalyzeMealRequest(mealId: mealId)
        if input.photos.isEmpty {
            request.description = words
            request.items = input.statedItems
        } else {
            request.imageBase64s = input.photos.map { $0.base64EncodedString() }
        }
        await analyze(request, attempts: input.photos.isEmpty ? Self.textAttempts : Self.photoAttempts)
        return mealId
    }

    /// Member-initiated do-over. Photo meals are re-read from storage by the server; text meals
    /// resend the words (new ones if given, else what the row still carries in `name`).
    func reanalyze(_ meal: MealLog, description: String?) async {
        var request = AnalyzeMealRequest(mealId: meal.id, reanalyze: true)
        let words = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if meal.photoPaths.isEmpty {
            request.description = words.isEmpty ? meal.name : words
        } else if !words.isEmpty {
            request.description = words
        }
        await analyze(request, attempts: meal.photoPaths.isEmpty ? Self.textAttempts : Self.photoAttempts)
    }

    private func analyze(_ request: AnalyzeMealRequest, attempts: Int) async {
        for attempt in 1...max(1, attempts) {
            do {
                try await backend.analyzeMeal(request)
                return
            } catch {
                Log.data.error("analyze-meal \(attempt)/\(attempts): \(String(describing: error), privacy: .public)")
            }
            if attempt < attempts, retryDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }
    }

    // MARK: Edits

    func updateNote(mealId: String, note: String?) async throws {
        try await backend.updateMealNote(mealId: mealId, note: Self.normalizeNote(note))
    }

    /// Photos first (best-effort), then the row. Deleting lives on meal detail only.
    func delete(_ meal: MealLog) async throws {
        if !meal.photoPaths.isEmpty {
            do { try await backend.removeMealPhotos(paths: meal.photoPaths) } catch {
                Log.data.error("meal.removePhotos: \(String(describing: error), privacy: .public)")
            }
        }
        try await backend.deleteMeal(id: meal.id)
    }

    // MARK: Photos

    func photoURL(path: String) async throws -> URL {
        if let cached = await photoURLs.url(for: path, now: now()) { return cached }
        let url = try await backend.mealPhotoURL(path: path)
        await photoURLs.store(url, for: path, expires: now().addingTimeInterval(Self.signedURLTTL - 30))
        return url
    }

    // MARK: Rules (pure)

    /// Same slots as the Expo app's `currentMealType()`.
    static func mealType(at date: Date, calendar: Calendar) -> MealLog.MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case ..<15: return .lunch
        case ..<18: return .snack
        default: return .dinner
        }
    }

    /// Mirrors the `nb_meal_logs_patient_note_shape` CHECK: null for no words, ≤ 2000 chars.
    static func normalizeNote(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= noteMaxLength { return trimmed }
        let cut = String(trimmed.prefix(noteMaxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }
}

/// Signed URLs are minted per path and reused until shortly before they expire.
actor PhotoURLCache {
    private var entries: [String: (url: URL, expires: Date)] = [:]

    func url(for path: String, now: Date) -> URL? {
        guard let entry = entries[path], entry.expires > now else { return nil }
        return entry.url
    }

    func store(_ url: URL, for path: String, expires: Date) {
        entries[path] = (url, expires)
    }
}
