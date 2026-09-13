import Foundation
import Observation

/// The plate can be CORRECTED after the fact (the Expo confirm screen's edit mode): portions rescale locally and
/// instantly; a renamed or hand-added food is UNPRICED and priced by `resolve-foods` one row at a time — never by
/// re-running the meal, so untouched rows cannot change. Save prices whatever is still unpriced first; a row the
/// resolver cannot price blocks the save with its name on screen, because a confident 0 kcal would be filed as fact.
@MainActor
@Observable
final class MealEditModel {
    /// The working copy — what is shown and edited. Adopted from the row exactly once.
    private(set) var working: MealDraft?
    private(set) var editing = false
    private(set) var dirty = false
    /// The explicit "Update nutrition" sweep is on screen.
    private(set) var reanalyzing = false
    /// Quiet background rounds (an add, a settled rename) — the "adding its calories…" line.
    private(set) var pricingCount = 0
    /// Already a human sentence. Nothing upstream reaches the screen.
    var error: String?
    /// The food the app just learned from a correction, for the thank-you toast.
    var learnedFood: String?

    let mealId: String
    private let meals: MealService
    private let members: MemberService
    private let origins = CorrectionOrigins()
    private var serverDraft: MealDraft?
    private var repriceTask: Task<Void, Never>?
    private var persistedOnExit = false
    /// The Expo rename debounce: a rename settles ~a second after the last keystroke, then the row is priced.
    static let repriceDelayMs = 1100

    init(mealId: String, meals: MealService, members: MemberService) {
        self.mealId = mealId
        self.meals = meals
        self.members = members
    }

    /// Adopt the server's analysis once; later snapshots must not clobber the member's edits.
    func adopt(_ meal: MealLog) {
        guard working == nil, let draft = MealDraft(meal: meal) else { return }
        working = draft
        serverDraft = draft
        origins.seed(draft.items)
    }

    /// A reviewed / re-priced draft handed in by another step (the photo review) replaces the working copy.
    func replace(with draft: MealDraft) {
        working = draft
        serverDraft = draft
        origins.seed(draft.items)
        dirty = false
    }

    /// The row as the screen should render it — the edits folded in.
    func display(_ meal: MealLog) -> MealLog { working?.applied(to: meal) ?? meal }

    var canAdjust: Bool { working != nil }

    var rows: [EditableRow] {
        (working?.items ?? []).enumerated().map { i, it in
            EditableRow(id: i, name: it.name, grams: it.estimatedGrams ?? 0, note: note(for: it), flagged: it.needsReview)
        }
    }

    private func note(for item: MealItem) -> String? {
        if item.needsReview { return String(localized: "meal.item.notCounted", defaultValue: "Not in our food database · not counted") }
        if let kcal = item.kcal { return "\(Int(kcal.rounded())) kcal" }
        return nil
    }

    func beginEdit() { editing = true }

    /// Back to whatever the pipeline last gave us, discarding the edits.
    func cancelEdit() {
        repriceTask?.cancel()
        working = serverDraft ?? working
        dirty = false
        error = nil
        editing = false
    }

    // MARK: Edits

    func rename(_ index: Int, to name: String) {
        guard var items = working?.items, items.indices.contains(index) else { return }
        items[index].name = name
        itemsChanged(items)
    }

    func setGrams(_ index: Int, _ grams: Double) {
        guard var items = working?.items, items.indices.contains(index) else { return }
        items[index] = MealEdit.scale(items[index], toGrams: grams)
        items[index].portionLabel = nil   // a hand-set number is not a reference
        itemsChanged(items)
    }

    func remove(_ index: Int) {
        guard var items = working?.items, items.indices.contains(index) else { return }
        items.remove(at: index)
        itemsChanged(items)
    }

    func add(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, var items = working?.items else { return }
        items.append(MealItem(name: n, estimatedGrams: 100))
        itemsChanged(items)
    }

    /// Portion / add / remove / rename → recompute totals + scores locally. A rename STRIPS the row's macros so
    /// it rejoins the same unpriced path as a hand-added row.
    private func itemsChanged(_ items: [MealItem]) {
        guard let current = working else { return }
        let prev = current.items
        let next = MealEdit.withRenamesUnpriced(prev: prev, next: items)
        origins.recordRenames(before: prev, after: next)
        working = MealEdit.recompute(current, items: next)
        dirty = true
        let renamed = prev.count == next.count && zip(prev, next).contains { $0.name != $1.name }
        if next.count == prev.count + 1, let added = next.last, MealEdit.isUnpriced(added) {
            Task { _ = await pricePendingItems() }
        } else if renamed || MealEdit.hasUnpricedPortionChange(prev: prev, next: next) {
            repriceTask?.cancel()
            repriceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Self.repriceDelayMs))
                guard !Task.isCancelled else { return }
                _ = await self?.pricePendingItems()
            }
        }
    }

    /// Quietly price whatever is unpriced in the CURRENT working copy. Returns the names it could not price.
    private func pricePendingItems() async -> [String] {
        let requests = MealEdit.pricingRequests(for: working?.items ?? [])
        guard !requests.isEmpty else { return [] }
        pricingCount += 1
        let resolved = await meals.resolvePricing(requests)
        pricingCount = max(0, pricingCount - 1)
        guard let resolved, let current = working else { return requests.map(\.name) }
        let merged = MealEdit.mergeResolvedPricing(items: current.items, requests: requests, resolved: resolved)
        working = MealEdit.recompute(current, items: merged.items)
        dirty = true
        return merged.unresolved
    }

    /// The explicit button: price everything still unpriced, with the sweep on screen. Returns the draft Save
    /// should persist (nil = nothing usable; the error banner is up).
    @discardableResult
    func updateNutrition() async -> MealDraft? {
        guard let current = working else { return nil }
        guard current.items.contains(where: MealEdit.isUnpriced) else { return current }
        error = nil
        editing = false
        reanalyzing = true
        let started = ContinuousClock.now
        let unresolved = await pricePendingItems()
        // Keep the sweep on screen long enough to read even when the resolver is quick.
        let elapsed = ContinuousClock.now - started
        if elapsed < .milliseconds(900) { try? await Task.sleep(for: .milliseconds(900) - elapsed) }
        reanalyzing = false
        if !unresolved.isEmpty {
            error = MealEdit.unresolvedMessage(unresolved)
            return nil
        }
        return working
    }

    /// Save: anything still unpriced gets priced FIRST so the saved totals include it.
    func save() async -> Bool {
        guard working != nil else { return false }
        repriceTask?.cancel()
        guard let final = await updateNutrition(), !final.items.contains(where: MealEdit.isUnpriced) else { return false }
        await persist(final)
        editing = false
        return true
    }

    /// Persist unsaved edits on the way out: a row whose debounced pricing has not landed yet is priced in the
    /// background first; if the resolver cannot price it, the row is saved unpriced (visibly missing beats plausibly wrong).
    func persistOnExit() {
        guard !persistedOnExit else { return }
        persistedOnExit = true
        guard dirty, let final = working else { return }
        repriceTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            if final.items.contains(where: MealEdit.isUnpriced) {
                let requests = MealEdit.pricingRequests(for: final.items)
                let resolved = await meals.resolvePricing(requests)
                let items = resolved.map { MealEdit.mergeResolvedPricing(items: final.items, requests: requests, resolved: $0).items } ?? final.items
                await persist(MealEdit.recompute(final, items: items))
            } else {
                await persist(final)
            }
        }
    }

    /// The row (best effort) + the learning loop, which the member's save never waits on.
    private func persist(_ draft: MealDraft) async {
        do { try await meals.updateAnalysis(mealId: mealId, draft: draft) } catch {
            Log.data.error("meal.updateAnalysis: \(String(describing: error), privacy: .public)")
        }
        serverDraft = draft
        dirty = false
        let corrections = origins.take(draft.items)
        if let first = corrections.first { learnedFood = first.toName }
        guard !corrections.isEmpty else { return }
        Task { [meals, members] in
            guard let member = try? await members.currentMember() else { return }
            for c in corrections { _ = await meals.learnCorrection(patientId: member.patientId, c) }
        }
    }
}

/// The photo flow's mid-flight confirmation (the Expo `PhotoPortionReview`): the identified foods with household
/// portions to point at, ON THE SAME SCREEN as the scan. The portions are REFERENCES, not multipliers.
@MainActor
@Observable
final class PhotoReviewModel {
    private(set) var working: MealDraft
    private(set) var pricing = false
    let reason: PhotoReview.Reason
    private let original: MealDraft
    private let meals: MealService

    init(draft: MealDraft, reason: PhotoReview.Reason, meals: MealService) {
        working = draft
        original = draft
        self.reason = reason
        self.meals = meals
    }

    var rows: [EditableRow] {
        working.items.enumerated().map { i, it in
            EditableRow(
                id: i, name: it.name, grams: it.estimatedGrams ?? 0,
                note: it.needsReview ? String(localized: "meal.item.notCounted", defaultValue: "Not in our food database · not counted") : it.kcal.map { "\(Int($0.rounded())) kcal" },
                flagged: it.needsReview
            )
        }
    }

    var unpricedCount: Int { working.items.filter(MealEdit.isUnpriced).count }
    var changed: Bool { working != original }

    private func apply(_ items: [MealItem]) { working = MealEdit.recompute(working, items: items) }

    /// A reference chip (records WHICH one) or the exact-grams path (clears the label).
    func setGrams(_ index: Int, _ grams: Double, label: String?) {
        guard working.items.indices.contains(index) else { return }
        var items = working.items
        items[index] = MealEdit.scale(items[index], toGrams: grams)
        items[index].portionLabel = label
        apply(items)
    }

    func rename(_ index: Int, to name: String) {
        guard working.items.indices.contains(index) else { return }
        var items = working.items
        items[index].name = name
        apply(MealEdit.withRenamesUnpriced(prev: working.items, next: items))
    }

    func remove(_ index: Int) {
        guard working.items.indices.contains(index) else { return }
        var items = working.items
        items.remove(at: index)
        apply(items)
    }

    func add(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        apply(working.items + [MealItem(name: n, estimatedGrams: 100)])
    }

    /// Anything renamed here is unpriced: priced BEFORE handing off, rather than leaving an item with no numbers.
    /// A transport failure hands the draft on as is — the meal page owns re-pricing and shows a real error there.
    func confirm() async -> MealDraft {
        let requests = MealEdit.pricingRequests(for: working.items)
        guard !requests.isEmpty else { return working }
        pricing = true
        let resolved = await meals.resolvePricing(requests)
        pricing = false
        guard let resolved else { return working }
        let merged = MealEdit.mergeResolvedPricing(items: working.items, requests: requests, resolved: resolved)
        apply(merged.items)
        return working
    }
}
