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

                    CheckinCarouselCard(
                        today: content.today,
                        now: dependencies.checkins.currentSlot,
                        streak: CheckinStreak.days(history: content.today.history, todayDone: !content.today.moments.isEmpty, today: content.today.day),
                        sleepHours: sleepHours
                    )

                    Button { capture.openPhotoChooser() } label: {
                        MealScanCard()
                    }
                    .buttonStyle(.plain)
                    .frame(height: 176)

                    gutRow(content.today)

                    MessagesCard(unread: content.today.unreadClinicianMessages)
                }
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }

    /// The daily gut check-in — done once, editable all day (the Expo hub's Gut Intelligence card).
    private func gutRow(_ today: TodaySnapshot) -> some View {
        let done = today.checkin?.isGutDone ?? false
        return NavigationLink(value: Route.gutCheckin) {
            HStack(spacing: 12) {
                Text("🫧").font(.system(size: 17))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "home.gut.title", defaultValue: "Gut check-in")).font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    Text(done ? String(localized: "home.gut.done", defaultValue: "✓ Done today · tap to adjust") : String(localized: "home.gut.sub", defaultValue: "Three quick reads · comfort, stool, food reactions"))
                        .font(FATypography.sans(10.5, .medium, relativeTo: .caption2)).foregroundStyle(done ? FAColor.accent : FAColor.inkSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
