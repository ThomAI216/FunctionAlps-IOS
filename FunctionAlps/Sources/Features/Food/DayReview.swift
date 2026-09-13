import SwiftUI
import Observation

/// "A whole day" — the Expo `day-review.tsx` on the async pipeline: every picked photo becomes a row up front
/// (a meal is a ROW first), the analyse calls run three at a time, each card is driven by its row's status
/// through a `MealWatcher`, and the member sets the meal slot per photo. Save keeps everything (the rows ARE the
/// save); ✕ is a real cancel that deletes the rows minted at kickoff.
enum DayBatch {
    static let analyzeConcurrency = 3

    /// Default slot by photo ORDER (the picker hands over pixels, not times): breakfast, lunch, dinner, then snacks.
    static func mealType(forIndex i: Int) -> MealLog.MealType {
        let order: [MealLog.MealType] = [.breakfast, .lunch, .dinner, .snack]
        return order[min(i, order.count - 1)]
    }

    enum Status: Sendable, Equatable { case pending, analyzing, done, error }

    /// DB row status → the card's vocabulary. `queued/identifying/pricing` = working; `complete` = done (the analysis
    /// travels with the row when it carries real numbers); `needs_input/failed` = error — the meal is KEPT, not lost.
    static func status(of meal: MealLog) -> Status {
        switch meal.status {
        case .complete: .done
        case .needsInput, .failed: .error
        case .queued, .identifying, .pricing: .analyzing
        }
    }

    struct Item: Identifiable, Sendable, Equatable {
        let id = UUID()
        let jpeg: Data
        var mealType: MealLog.MealType
        var status: Status = .pending
        var mealId: String? = nil
        var meal: MealLog? = nil
    }

    /// Row-backed photos count even mid-analysis — the row IS the save.
    static func saveable(_ items: [Item]) -> Int { items.filter { $0.mealId != nil }.count }
}

@MainActor
@Observable
final class DayReviewModel {
    private(set) var items: [DayBatch.Item]
    private(set) var saving = false
    private let meals: MealService
    private let members: MemberService
    private var watchers: [UUID: MealWatcher] = [:]
    private var runner: Task<Void, Never>?
    private var started = false

    init(photos: [Data], meals: MealService, members: MemberService) {
        items = photos.enumerated().map { i, jpeg in DayBatch.Item(jpeg: jpeg, mealType: DayBatch.mealType(forIndex: i)) }
        self.meals = meals
        self.members = members
    }

    /// Only photos without a row hold the member here; row-backed ones are already meals the worker finishes.
    var busy: Bool { items.contains { $0.mealId == nil && ($0.status == .pending || $0.status == .analyzing) } }
    var stillWorking: Bool { items.contains { $0.mealId != nil && ($0.status == .pending || $0.status == .analyzing) } }
    var saveable: Int { DayBatch.saveable(items) }

    /// Kick the whole batch through the pipeline exactly once: rows are minted as each capture starts, at most
    /// three captures (upload + analyse) in flight; each row is watched from the moment it exists.
    func start() {
        guard !started else { return }
        started = true
        let snapshot = items
        runner = Task { [weak self] in
            guard let self, let member = try? await members.currentMember() else { return }
            await withTaskGroup(of: Void.self) { group in
                for (index, item) in snapshot.enumerated() {
                    if index >= DayBatch.analyzeConcurrency { await group.next() }
                    if Task.isCancelled { break }
                    group.addTask { [meals] in
                        _ = try? await meals.capture(MealCaptureInput(photos: [item.jpeg], source: .photo, mealType: item.mealType), patientId: member.patientId, userId: member.userId) { id in
                            await self.rowCreated(item.id, id)
                        }
                    }
                }
            }
        }
    }

    private func rowCreated(_ itemId: UUID, _ mealId: String) {
        guard let i = items.firstIndex(where: { $0.id == itemId }) else {
            // Removed while its insert was in flight: a meal nobody will review — delete it rather than surprise the day.
            Task { [meals] in await meals.discard(id: mealId) }
            return
        }
        items[i].mealId = mealId
        items[i].status = .analyzing
        let w = MealWatcher(meals: meals)
        watchers[itemId] = w
        w.start(id: mealId, maxWait: .seconds(150)) { [weak self] meal in
            guard let self, let i = self.items.firstIndex(where: { $0.id == itemId }) else { return }
            self.items[i].meal = meal
            self.items[i].status = DayBatch.status(of: meal)
        }
    }

    /// The row was minted with the slot the photo ORDER guessed; a re-slot must reach it directly.
    func setType(_ item: DayBatch.Item, _ type: MealLog.MealType) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].mealType = type
        if let id = item.mealId { Task { [meals] in await meals.setMealType(id: id, type) } }
    }

    /// Removing a row-backed photo must also remove the MEAL — the row exists and would complete on its own.
    func remove(_ item: DayBatch.Item) {
        watchers[item.id]?.stop()
        watchers[item.id] = nil
        items.removeAll { $0.id == item.id }
        if let id = item.mealId { Task { [meals] in await meals.discard(id: id) } }
    }

    /// Save all: the rows are already meals; still-working ones finish server-side with nobody watching.
    func saveAll() {
        saving = true
        stopWatching()
    }

    /// ✕ = cancel, and under the async pipeline cancel must UNDO: the rows exist. Best-effort deletes.
    func cancelAll() {
        stopWatching()
        let ids = items.compactMap(\.mealId)
        Task { [meals] in for id in ids { await meals.discard(id: id) } }
        items = []
    }

    private func stopWatching() {
        runner?.cancel()
        for w in watchers.values { w.stop() }
        watchers = [:]
    }
}

/// The review: one card per photo (thumbnail, the row's state, kcal once real, the four slot chips), Save all.
struct DayReviewView: View {
    @Environment(AppDependencies.self) private var dependencies
    let photos: [Data]
    let onFinished: () -> Void
    @State private var model: DayReviewModel?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(String(localized: "day.title", defaultValue: "Your day")).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.ink)
                        Spacer()
                        Button { model?.cancelAll(); onFinished() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.charcoal)
                                .frame(width: 34, height: 34).background(Color.white.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "action.cancel", defaultValue: "Cancel"))
                    }
                    .padding(.top, 10).padding(.bottom, 6)
                    Text(String(localized: "day.subtitle", defaultValue: "Set the meal for each photo, then save them all."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                        .padding(.bottom, (model?.stillWorking ?? false) ? 4 : 14)
                    if model?.stillWorking ?? false {
                        Text(String(localized: "day.stillWorking", defaultValue: "Photos still being read finish on their own · no need to wait for them."))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).padding(.bottom, 14)
                    }
                    if let model {
                        if model.items.isEmpty {
                            Text(String(localized: "day.empty", defaultValue: "No photos to review.")).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).padding(.vertical, 20)
                        } else {
                            ForEach(model.items) { item in card(item, model) }
                            saveButton(model)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .faWall()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if model == nil {
                let m = DayReviewModel(photos: photos, meals: dependencies.meals, members: dependencies.members)
                model = m
                m.start()
            }
        }
    }

    private func card(_ item: DayBatch.Item, _ model: DayReviewModel) -> some View {
        let analyzing = item.status == .pending || item.status == .analyzing
        let failed = item.status == .error
        return FACard {
            HStack(alignment: .top, spacing: 12) {
                if let image = UIImage(data: item.jpeg) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(analyzing ? String(localized: "capture.reading", defaultValue: "Your plate, read.")
                             : failed ? String(localized: "day.failed", defaultValue: "Couldn’t read this photo")
                             : (item.meal?.name ?? String(localized: "meal.type.other", defaultValue: "Meal")))
                            .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(failed ? Color(hex: 0xC0453A) : FAColor.ink).lineLimit(1)
                        Spacer(minLength: 0)
                        Button { model.remove(item) } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkSecondary).frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                    if analyzing {
                        HStack(spacing: 7) {
                            ProgressView().tint(FAColor.forestSoft).scaleEffect(0.7)
                            Text(String(localized: "day.analyzing", defaultValue: "analyzing…")).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                        }
                        .padding(.top, 6)
                    } else if failed {
                        Text(String(localized: "day.failed.kept", defaultValue: "We couldn’t read this one. It’s kept in your log · add details or remove it there."))
                            .font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(Int((item.meal?.totalCalories ?? 0).rounded())) kcal").font(FATypography.sans(11.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft).padding(.top, 3)
                    }
                    HStack(spacing: 6) {
                        ForEach([MealLog.MealType.breakfast, .lunch, .dinner, .snack], id: \.self) { type in
                            let active = item.mealType == type
                            Button { model.setType(item, type) } label: {
                                Text(type.localizedName).font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).foregroundStyle(active ? FAColor.charcoal : FAColor.inkSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(active ? FAColor.forestSoft : Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(active ? FAColor.forestSoft : FAColor.separator, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func saveButton(_ model: DayReviewModel) -> some View {
        let n = model.saveable
        let title = model.busy ? String(localized: "day.save.analyzing", defaultValue: "Analyzing…")
            : model.saving ? String(localized: "day.save.saving", defaultValue: "Saving…")
            : (n == 1 ? String(localized: "day.save.one", defaultValue: "Save all · 1 meal") : String(localized: "day.save.many", defaultValue: "Save all · \(n) meals"))
        return FAButton(title: title, isEnabled: !model.busy && !model.saving && n > 0) {
            model.saveAll()
            onFinished()
        }
        .padding(.top, 6)
    }
}
