import SwiftUI

struct MealDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let mealId: String
    @State private var model: MealDetailViewModel?
    @State private var editingNote = false
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            FAColor.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = MealDetailViewModel(mealId: mealId, meals: dependencies.meals, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
        .onDisappear { model?.cancel() }
    }

    @ViewBuilder
    private func content(_ model: MealDetailViewModel) -> some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "meal.error.title", defaultValue: "Couldn't load this meal"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            FAErrorState(title: String(localized: "meal.missing.title", defaultValue: "Meal not found"), message: String(localized: "meal.missing.message", defaultValue: "It may have been deleted."), retryTitle: nil, retry: nil)
        case .loaded(let meal):
            ScrollView {
                VStack(alignment: .leading, spacing: FASpacing.lg) {
                    if meal.photoPath != nil {
                        MealPhotoView(path: meal.photoPath, width: nil, height: 240, cornerRadius: FACornerRadius.lg)
                    }
                    header(meal)
                    if meal.status != .complete { statusCard(meal) }
                    macros(meal)
                    if let scores = meal.scores { MealScoresCard(scores: scores) }
                    if !meal.items.isEmpty { MealItemsCard(items: meal.items) }
                    noteCard(meal, model)
                    FAButton(title: String(localized: "meal.delete", defaultValue: "Delete this meal"), style: .destructive, isLoading: model.isDeleting) {
                        confirmDelete = true
                    }
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load() }
            .confirmationDialog(String(localized: "meal.delete.confirm", defaultValue: "Delete this meal? This can't be undone."), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(String(localized: "meal.delete", defaultValue: "Delete this meal"), role: .destructive) {
                    Task { if await model.delete() { dismiss() } }
                }
            }
            .sheet(isPresented: $editingNote) {
                NoteEditor(model: model)
                    .presentationDetents([.medium, .large])
            }
            .alert(String(localized: "error.title", defaultValue: "Something went wrong"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func header(_ meal: MealLog) -> some View {
        VStack(alignment: .leading, spacing: FASpacing.xs) {
            Text([meal.mealType?.localizedName, meal.loggedAt.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(FATypography.label)
                .foregroundStyle(FAColor.accent)
                .tracking(0.8)
            Text(meal.displayName)
                .font(FATypography.largeTitle)
                .foregroundStyle(FAColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusCard(_ meal: MealLog) -> some View {
        FACard {
            switch meal.status {
            case .queued, .identifying, .pricing:
                Label(String(localized: "meal.status.analyzingLong", defaultValue: "Still being analysed — this page updates by itself."), systemImage: "sparkles")
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.accent)
            case .needsInput:
                Label(String(localized: "meal.status.needsInputLong", defaultValue: "We couldn't read this meal fully. Log it again with a few words to get the numbers."), systemImage: "questionmark.circle")
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.warning)
            case .failed:
                Label(String(localized: "meal.status.failedLong", defaultValue: "The analysis failed. You can delete this meal and log it again."), systemImage: "exclamationmark.circle")
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.danger)
            case .complete:
                EmptyView()
            }
        }
    }

    private func macros(_ meal: MealLog) -> some View {
        HStack(spacing: FASpacing.sm) {
            FAMetricCard(label: String(localized: "macros.energy", defaultValue: "Energy"), value: Format.kcal(meal.totalCalories ?? 0))
            FAMetricCard(label: String(localized: "macros.protein", defaultValue: "Protein"), value: Format.grams(meal.totalProteinG ?? 0))
            FAMetricCard(label: String(localized: "macros.carbs", defaultValue: "Carbs"), value: Format.grams(meal.totalCarbsG ?? 0))
            FAMetricCard(label: String(localized: "macros.fat", defaultValue: "Fat"), value: Format.grams(meal.totalFatG ?? 0))
        }
    }

    /// The member's words. Labelled as theirs, never beside model text under one heading.
    private func noteCard(_ meal: MealLog, _ model: MealDetailViewModel) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                HStack {
                    Text(String(localized: "meal.note.title", defaultValue: "In your words"))
                        .font(FATypography.headline)
                        .foregroundStyle(FAColor.ink)
                    Spacer()
                    Button(meal.patientNote == nil
                           ? String(localized: "meal.note.add", defaultValue: "Add")
                           : String(localized: "meal.note.edit", defaultValue: "Edit")) {
                        model.noteDraft = meal.patientNote ?? ""
                        editingNote = true
                    }
                    .font(FATypography.label)
                    .foregroundStyle(FAColor.brand)
                }
                if let note = meal.patientNote {
                    Text(note)
                        .font(FATypography.body)
                        .foregroundStyle(FAColor.ink)
                } else {
                    Text(String(localized: "meal.note.placeholder", defaultValue: "How did it feel? Where were you? Anything you want your nutritionist to know."))
                        .font(FATypography.callout)
                        .foregroundStyle(FAColor.inkMuted)
                }
            }
        }
    }
}

private struct NoteEditor: View {
    @Bindable var model: MealDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FAColor.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: FASpacing.sm) {
                    TextEditor(text: $model.noteDraft)
                        .font(FATypography.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                        .frame(minHeight: 160)
                    Text(String(localized: "meal.note.limit", defaultValue: "\(model.noteDraft.count) / \(MealService.noteMaxLength)"))
                        .font(FATypography.caption)
                        .foregroundStyle(model.noteDraft.count > MealService.noteMaxLength ? FAColor.danger : FAColor.inkMuted)
                    Spacer()
                }
                .padding(FASpacing.md)
            }
            .navigationTitle(String(localized: "meal.note.title", defaultValue: "In your words"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save", defaultValue: "Save")) {
                        Task { if await model.saveNote() { dismiss() } }
                    }
                    .disabled(model.isSavingNote)
                }
            }
        }
    }
}
