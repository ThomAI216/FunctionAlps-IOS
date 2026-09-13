import Foundation
import Observation

/// "Say or type your meal, watch the ingredients appear" — the whole loop, in one place (the Expo
/// `useMealDictation` + `meal-preprocess-store`): debounce + coalesce + one in flight, the list survives
/// re-extraction, and the model's follow-up questions are answered into the RIGHT field. Shared by the Food tab's
/// describe card and the capture screen's "tell us what you ate" card, so there is one machine, not two.
@MainActor
@Observable
final class MealDictationModel {
    var description = ""
    let dictation: SpeechDictation
    /// The extracted list, editable — kept visible while the next extraction runs.
    private(set) var items: [MealPreprocess.Item] = []
    private(set) var clarifications: [MealClarification] = []
    private(set) var extracting = false
    private(set) var errorMessage: String?
    /// The last words in the field came from the microphone (the capture's `source`).
    private(set) var spoke = false

    private var lastExtracted = ""
    private var extractTask: Task<Void, Never>?
    private var pendingExtract: String?
    private let meals: MealService
    private let mealType: @MainActor () -> MealLog.MealType?
    /// The Expo `LIVE_EXTRACT_DEBOUNCE_MS`.
    static let debounceMs = 700

    init(meals: MealService, mealType: @escaping @MainActor () -> MealLog.MealType? = { nil }) {
        self.meals = meals
        self.mealType = mealType
        dictation = SpeechDictation { audio, mime in try await meals.transcribe(audio: audio, mimeType: mime) }
        dictation.onFinal = { [weak self] words in
            guard let self else { return }
            let current = self.description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.description = current.isEmpty ? words : current + " " + words
            self.spoke = true
            // Whisper: the whole thing arrives at once, so extract straight away — the person already waited.
            self.extractTask?.cancel()
            Task { await self.extract(self.description.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    var hasItems: Bool { !items.isEmpty }
    /// An open question blocks Analyse: an unanswered "which cheese?" would price the wrong food.
    var blocked: Bool { !clarifications.isEmpty }
    var canAnalyse: Bool { !blocked && !extracting && (hasItems || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    /// Wire to the field: every edit re-extracts after the debounce.
    func typedChanged() {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { clearExtraction(); return }
        extractTask?.cancel()
        extractTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.debounceMs))
            guard !Task.isCancelled else { return }
            await self?.extract(text)
        }
    }

    private func clearExtraction() {
        extractTask?.cancel()
        extractTask = nil
        pendingExtract = nil
        lastExtracted = ""
        items = []
        clarifications = []
        errorMessage = nil
    }

    /// Debounce + coalesce + one in flight: only the newest pending text survives a running extraction.
    private func extract(_ text: String) async {
        guard text.count >= 3, text != lastExtracted else { return }
        if extracting { pendingExtract = text; return }
        extracting = true
        lastExtracted = text
        errorMessage = nil
        do {
            let result = try await meals.preprocess(text, mealType: mealType())
            items = result.items
            clarifications = result.clarifications
        } catch {
            Log.data.error("meal.preprocess: \(String(describing: error), privacy: .public)")
            if items.isEmpty { errorMessage = String(localized: "food.describe.extractFailed", defaultValue: "Couldn’t list the ingredients just now · your words are kept, try again or analyse as typed.") }
        }
        extracting = false
        if let queued = pendingExtract { pendingExtract = nil; await extract(queued) }
    }

    // MARK: Answers + edits (the Expo store actions)

    /// WHERE the answer goes depends on WHAT WAS ASKED (`kind`).
    func resolveClarification(_ c: MealClarification, option: String) {
        guard items.indices.contains(c.itemIndex) else { dismissClarification(c); return }
        items[c.itemIndex] = ClarificationLogic.apply(option, kind: c.kind, to: items[c.itemIndex])
        clarifications.removeAll { $0.itemIndex == c.itemIndex }
    }

    /// "It's fine as is": keep the item exactly as detected, drop the question.
    func dismissClarification(_ c: MealClarification) {
        clarifications.removeAll { $0.itemIndex == c.itemIndex }
    }

    func rename(_ index: Int, to name: String) {
        guard items.indices.contains(index) else { return }
        items[index].name = name
        items[index].confidence = "high"
        clarifications.removeAll { $0.itemIndex == index }
    }

    func setGrams(_ index: Int, _ grams: Double) {
        guard items.indices.contains(index) else { return }
        items[index].estimatedG = max(5, Int(grams.rounded()))
        items[index].confidence = "high"
        clarifications.removeAll { $0.itemIndex == index }
    }

    func remove(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        clarifications = clarifications.filter { $0.itemIndex != index }.map { c in
            var c = c
            if c.itemIndex > index { c.itemIndex -= 1 }
            return c
        }
    }

    func add(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        items.append(MealPreprocess.Item(name: n, quantity: nil, estimatedG: 100, volumeMeasure: nil, confidence: "high"))
    }

    // MARK: What leaves

    /// A HUMAN-READABLE summary — what the member reads back and what lands transiently in `name`. NOT the transport.
    func confirmedDescription() -> String {
        if items.isEmpty { return description.trimmingCharacters(in: .whitespacesAndNewlines) }
        return items.map { "\($0.name) \($0.estimatedG)g" }.joined(separator: ", ")
    }

    /// The STRUCTURED list — what reaches `analyze-meal`, where the grams are a field rather than a substring.
    func confirmedItems() -> [StatedItem] { items.compactMap(\.stated) }

    /// Hands the meal to the capture flow and clears the card. Nil while nothing usable is there.
    func takeCapture() -> MealCaptureInput? {
        guard canAnalyse else { return nil }
        let desc = confirmedDescription()
        guard !desc.isEmpty else { return nil }
        var input = MealCaptureInput(description: desc, source: spoke ? .voice : .text)
        input.statedItems = confirmedItems()
        reset()
        return input
    }

    /// The words split into lines — the fallback while nothing is extracted yet (the Expo `parseMealDescriptionToCandidate`).
    var describedLines: [String] {
        description
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " et ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func reset() {
        description = ""
        spoke = false
        clearExtraction()
    }
}
