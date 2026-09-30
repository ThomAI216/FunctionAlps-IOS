import SwiftUI

/// Home: functional hero → the two squares (log a meal · the evening check-in) → today's actions →
/// Apple Health's readings as charts → messages. The owner's layout (2026-09-30): one check-in a day, in the
/// evening, with digestion inside it; no separate focus or digestion cards.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model: HomeViewModel?
    @State private var capture = MealCaptureCoordinator()

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
            let notifications = dependencies.notifications, wearables = dependencies.wearables, focus = dependencies.focus, habits = dependencies.habits
            Task { await focus.load() }   // read back — the day is computed once and holds still
            Task { await habits.load(patientId: patientId, day: today.day) }
            Task {
                await notifications.loadPrefs(patientId: patientId)
                await notifications.refreshAuthorization()
                await notifications.replan(snapshot: today, wearables: wearables)
                await wearables.refreshSnapshot()
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
                    ProtocolReviewCard()

                    HStack(spacing: 12) {
                        Button { capture.openPhotoChooser() } label: {
                            MealScanCard()
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(1, contentMode: .fit)

                        EveningCheckinCard(
                            today: content.today,
                            now: dependencies.checkins.currentSlot,
                            streak: CheckinStreak.days(history: content.today.history, todayDone: !content.today.moments.isEmpty, today: content.today.day)
                        )
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .frame(maxHeight: 230)

                    PlanTodayCard()

                    if content.today.checkin?.redFlags.any == true {
                        RedFlagSignpostCard()
                    }

                    if HealthKitReader.isAvailable {
                        healthReadings
                    }

                    MessagesCard(unread: content.today.unreadClinicianMessages)
                }
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }

    /// Apple Health straight as its charts once connected; the invitation until then.
    @ViewBuilder
    private var healthReadings: some View {
        let wearables = dependencies.wearables
        if !wearables.isConnected {
            NavigationLink(value: Route.wearables) { AppleHealthConnectCard() }
                .buttonStyle(.plain)
        } else if let snapshot = wearables.snapshot {
            if snapshot.hasAnyReading {
                HealthCharts(snapshot: snapshot)
            } else {
                FACard {
                    Text(String(localized: "home.health.empty", defaultValue: "No readings yet · open the Health app on your iPhone to check what it holds."))
                        .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            FACard {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "home.health.reading", defaultValue: "Reading Health…")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }
}
