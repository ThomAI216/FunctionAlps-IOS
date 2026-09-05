import SwiftUI

/// The web app's Home, card for card: functional hero → the two action squares → messages.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model: HomeViewModel?
    @State private var capture = MealCaptureCoordinator()
    /// Last night's sleep for the carousel chip — Apple Health first, else the member's own morning answer.
    @State private var sleepHours: Double?

    var body: some View {
        ZStack {
            if let model {
                content(model)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .mealCaptureHost(capture) { Task { await model?.load(refresh: true) } }
        .task {
            if model == nil {
                let m = HomeViewModel(members: dependencies.members, dashboard: dependencies.dashboard, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
        .onAppear {
            // Returning from a pushed screen (a saved check-in, a deleted meal): refresh in place.
            if let model, model.state.value != nil { Task { await model.load(refresh: true) } }
        }
        .onChange(of: model?.state.value?.today) { _, today in
            // Every fresh Today re-plans the phone's reminders (done moments dropped, logged meals dropped).
            guard let today, let patientId = model?.state.value?.member.patientId else { return }
            let notifications = dependencies.notifications, wearables = dependencies.wearables
            Task {
                await notifications.loadPrefs(patientId: patientId)
                await notifications.refreshAuthorization()
                await notifications.replan(snapshot: today, wearables: wearables)
                let fromHealth = await wearables.lastNightSleepHours()
                let fromAnswer = today.moments.first { $0.slot == .morning }?.sleepDurationMin.map { Double($0) / 60 }
                sleepHours = fromHealth ?? fromAnswer
            }
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "home.error.title", defaultValue: "Couldn't load today"), message: error.userMessage) {
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
                VStack(spacing: 12) {
                    Button { router.tab = .trends } label: {
                        FunctionalHeroCard(today: content.today)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button { capture.openPhotoChooser() } label: {
                            MealScanCard()
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(1, contentMode: .fit)

                        CheckinCarouselCard(
                            today: content.today,
                            now: dependencies.checkins.currentSlot,
                            streak: CheckinStreak.days(history: content.today.history, todayDone: !content.today.moments.isEmpty, today: content.today.day),
                            sleepHours: sleepHours
                        )
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .frame(maxHeight: 230)

                    NavigationLink(value: Route.gutCheckin) {
                        GutCheckinCard(done: content.today.checkin?.isGutDone ?? false, score: content.today.checkin?.gutOverall)
                    }
                    .buttonStyle(.plain)

                    MessagesCard(unread: content.today.unreadClinicianMessages)
                }
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }
}
