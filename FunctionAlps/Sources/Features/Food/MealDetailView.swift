import SwiftUI

/// A logged meal, days later — the Expo `meal-detail/[id].tsx`: the photo with the name over it,
/// the macro line, the ingredients with their flags, how it felt, the member's own words, the three
/// score cards (tap to understand), then delete.
struct MealDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let mealId: String
    @State private var model: MealDetailViewModel?
    @State private var editingNote = false
    @State private var confirmDelete = false
    @State private var explaining: MealScoreKind?

    var body: some View {
        ZStack {
            if let model {
                content(model)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
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
                VStack(alignment: .leading, spacing: 0) {
                    backRow(meal)
                    hero(meal)
                    MacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
                        .padding(.top, 14)
                    if meal.status != .complete { statusCard(meal).padding(.top, 14) }
                    if !meal.items.isEmpty { ingredients(meal) }
                    feltSection(model.reaction)
                    noteCard(meal, model).padding(.top, 16)
                    if let scores = meal.scores { scoreCards(scores) }
                    FAButton(title: String(localized: "meal.delete", defaultValue: "Delete this meal"), style: .destructive, isLoading: model.isDeleting) {
                        confirmDelete = true
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 18)
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
            .sheet(item: $explaining) { kind in
                if let scores = meal.scores {
                    ScoreExplainerSheet(kind: kind, value: kind.value(in: scores)).presentationDetents([.medium])
                }
            }
            .alert(String(localized: "error.title", defaultValue: "Something went wrong"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func backRow(_ meal: MealLog) -> some View {
        Button { dismiss() } label: {
            Text("‹ " + (meal.mealType?.localizedName ?? String(localized: "meal.type.other", defaultValue: "Meal")))
                .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// The real photo when we have it, otherwise the meal-type illustration — the name over a soft veil.
    private func hero(_ meal: MealLog) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let path = meal.photoPath {
                    MealPhotoView(path: path, width: nil, height: 150, cornerRadius: 16)
                } else {
                    AsyncImage(url: MealPlaceholderImage.url(mealType: meal.mealType, dishName: meal.name ?? "")) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { FAColor.surfaceMuted }
                    }
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x14140F, opacity: 0.28)).frame(height: 150)
            if meal.photoPath == nil {
                Text(String(localized: "meal.mockup", defaultValue: "Mockup image · to illustrate your plate"))
                    .font(FATypography.sans(9, .semibold, relativeTo: .caption2)).foregroundStyle(Color(hex: 0xB9B4A8))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color(hex: 0x14140F, opacity: 0.5), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
            Text(meal.displayName).font(FATypography.display(18, relativeTo: .title3)).foregroundStyle(.white).padding(14)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meal.displayName)
    }

    private func statusCard(_ meal: MealLog) -> some View {
        FACard {
            switch meal.status {
            case .queued, .identifying, .pricing:
                Label(String(localized: "meal.status.analyzingLong", defaultValue: "Still being analysed — this page updates by itself."), systemImage: "sparkles")
                    .font(FATypography.callout).foregroundStyle(FAColor.accent)
            case .needsInput:
                Label(String(localized: "meal.status.needsInputLong", defaultValue: "We couldn't read this meal fully. Log it again with a few words to get the numbers."), systemImage: "questionmark.circle")
                    .font(FATypography.callout).foregroundStyle(FAColor.warning)
            case .failed:
                Label(String(localized: "meal.status.failedLong", defaultValue: "The analysis failed. You can delete this meal and log it again."), systemImage: "exclamationmark.circle")
                    .font(FATypography.callout).foregroundStyle(FAColor.danger)
            case .complete:
                EmptyView()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(11, .bold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.inkSecondary)
    }

    /// Per-item macros + food flags (`nb_meal_logs.ai_identified_foods`).
    private func ingredients(_ meal: MealLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(String(localized: "meal.ingredients", defaultValue: "Ingredients"))
            VStack(spacing: 0) {
                ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
                    MealItemRow(item: item)
                    Divider().overlay(FAColor.separator)
                }
            }
        }
        .padding(.top, 18)
    }

    /// The past felt-reaction (`nb_meal_reactions`): a sentiment dot + word + the top flags.
    private func feltSection(_ reaction: MealReaction?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "meal.felt", defaultValue: "How it felt"))
            if let reaction, let sentiment = reaction.sentiment {
                let tone: Color = sentiment == .good ? Color(hex: 0x4A8A5C) : sentiment == .watch ? Color(hex: 0xC99A3B) : Color(hex: 0xC0453A)
                let word = sentiment == .good ? String(localized: "meal.felt.good", defaultValue: "Sat well") : sentiment == .watch ? String(localized: "meal.felt.watch", defaultValue: "A bit off") : String(localized: "meal.felt.bad", defaultValue: "Rough")
                let labels = reaction.flagLabels()
                HStack(spacing: 5) {
                    Circle().fill(tone).frame(width: 6, height: 6)
                    Text(word).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(tone)
                    if !labels.isEmpty {
                        Text("· " + labels.joined(separator: ", ")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            } else {
                Text(String(localized: "meal.felt.unrated", defaultValue: "How did it feel?")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
            }
        }
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }

    /// The member's words. Labelled as theirs, never beside model text under one heading.
    private func noteCard(_ meal: MealLog, _ model: MealDetailViewModel) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                HStack {
                    Text(String(localized: "meal.note.title", defaultValue: "In your words"))
                        .font(FATypography.headline).foregroundStyle(FAColor.ink)
                    Spacer()
                    Button(meal.patientNote == nil
                           ? String(localized: "meal.note.add", defaultValue: "Add")
                           : String(localized: "meal.note.edit", defaultValue: "Edit")) {
                        model.noteDraft = meal.patientNote ?? ""
                        editingNote = true
                    }
                    .font(FATypography.label).foregroundStyle(FAColor.brand)
                }
                if let note = meal.patientNote {
                    Text(note).font(FATypography.body).foregroundStyle(FAColor.ink)
                } else {
                    Text(String(localized: "meal.note.placeholder", defaultValue: "How did it feel? Where were you? Anything you want your nutritionist to know."))
                        .font(FATypography.callout).foregroundStyle(FAColor.inkMuted)
                }
            }
        }
    }

    /// The three scores as tappable glass cards: ring · title · verdict · Understand ›.
    private func scoreCards(_ scores: MealScores) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "meal.scores.heading", defaultValue: "How this meal scored")).padding(.top, 24).padding(.bottom, 2)
            ForEach(MealScoreKind.allCases) { kind in
                let value = kind.value(in: scores)
                Button { explaining = kind } label: {
                    FACard {
                        HStack(spacing: 13) {
                            ScoreWheel(value: value, color: kind.color, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Text(kind.verdict(value)).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.leading)
                                Text(String(localized: "meal.score.understand", defaultValue: "Understand ›")).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forestSoft).padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title): \(value) out of 100. \(kind.verdict(value))")
            }
            Text(String(localized: "meal.scores.tapHint", defaultValue: "Tap any score to understand it ↑"))
                .font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                .frame(maxWidth: .infinity).padding(.top, 4)
        }
    }
}

private struct NoteEditor: View {
    @Bindable var model: MealDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
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
