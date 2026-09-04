import PhotosUI
import SwiftUI

struct FoodView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: FoodViewModel?

    var body: some View {
        ZStack {
            if let model {
                FoodScreen(model: model)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = FoodViewModel(members: dependencies.members, meals: dependencies.meals, auth: dependencies.auth)
                let notifications = dependencies.notifications
                m.onMealLogged = { id in Task { await notifications.mealLogged(id: id, at: Date()) } }
                model = m
                await m.load()
            }
        }
    }
}

/// The Expo `(tabs)/log.tsx`, card for card: the macros/micros/nutri-score lead card, the capture
/// glass card (photo scan hero · favorites · describe), then the recent meals with no label.
private struct FoodScreen: View {
    @Bindable var model: FoodViewModel
    @Environment(AppRouter.self) private var router
    @State private var capture = MealCaptureCoordinator()

    var body: some View {
        content
            .mealCaptureHost(capture) { model.captureFinished() }
            .onAppear {
                guard router.pendingCapture else { return }
                router.pendingCapture = false
                capture.openPhotoChooser()
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.spring(duration: 0.35, bounce: 0.15), value: model.relogToast)
            .alert(String(localized: "food.error.title", defaultValue: "Couldn't load your meals"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "food.error.title", defaultValue: "Couldn't load your meals"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            FAErrorState(
                title: String(localized: "home.notRegistered.title", defaultValue: "Almost there"),
                message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."),
                retryTitle: String(localized: "action.retry", defaultValue: "Try again")
            ) { Task { await model.load() } }
        case .loaded(let content):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        router.push(content.member.profile?.hasBodyData == true ? .macros : .nutritionTargets)
                    } label: {
                        MacrosTodayCard(
                            todayMeals: model.todayMeals(content),
                            profile: content.member.profile,
                            microTrend: model.microTrend(content),
                            todayScores: model.todayScores(content),
                            onMacroTap: { router.push(.macro($0)) }
                        )
                    }
                    .buttonStyle(.plain)
                    captureCard.padding(.top, 14)
                    recent(content).padding(.top, 22)
                }
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load(refresh: true) }
        }
    }

    /// Photo · favorites · Describe — one capture card with the forest 0.45 border.
    private var captureCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                PhotoScanCard { capture.openPhotoChooser() }
                FavoritesStrip(favorites: model.favorites) { fav in
                    model.relog(RelogSource(favorite: fav), favoriteId: fav.id)
                }
                DescribeMealBare(model: model) {
                    if let input = model.takeTextCapture() { capture.begin(input) }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(FoodPalette.hairline).frame(height: 1) }
                .padding(.top, 12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                .strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.45), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func recent(_ content: FoodViewModel.Content) -> some View {
        let meals = model.recentMeals(content)
        if meals.isEmpty {
            Button { capture.openPhotoChooser() } label: {
                Text(String(localized: "food.empty.cta", defaultValue: "＋ No meals yet · snap your first"))
                    .font(FATypography.sans(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(FoodPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(FoodPalette.hairline)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(meals) { meal in
                    LogMealCard(
                        meal: meal,
                        reaction: model.reactions[meal.id],
                        isFavorite: model.isFavorite(meal),
                        when: model.when(meal.loggedAt),
                        onRelog: { model.relog(RelogSource(meal: meal)) },
                        onToggleFavorite: { model.toggleFavorite(meal) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let t = model.relogToast {
            RelogToast(name: t.name, kcal: t.kcal) {
                if let id = model.adjustRelog() { router.foodPath.append(.meal(id)) }
            } onUndo: {
                model.undoRelog()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
