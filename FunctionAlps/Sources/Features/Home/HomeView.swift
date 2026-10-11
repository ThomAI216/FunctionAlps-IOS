import SwiftUI

/// Home (owner's layout, 2026-09-30): the Foundation Track's day while the member is on it (2026-10-06) →
/// "My health plan" (objective, phase, goals, priorities) → today's actions
/// → the two squares (log a meal · the evening check-in) → the doctor signpost when raised → "Worth a look
/// together" → messages. A place to understand and act, not a scoreboard: the scores and Apple Health's charts
/// live in Trends. One check-in a day, in the evening, with digestion inside it.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: HomeViewModel?
    @State private var capture = MealCaptureCoordinator()
    /// The Foundation Track questionnaire on screen — owned here, above the card, so a submit that changes or hides
    /// the card never tears the flow down.
    @State private var questionnaire: TrackQuestionnaireRef?

    var body: some View {
        ZStack {
            if let model {
                content(model)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .mealCaptureHost(capture) { Task { await model?.load(refresh: true) } }
        .fullScreenCover(item: $questionnaire) { TrackQuestionnaireView(questionnaireId: $0.id) }
        .onChange(of: dependencies.track.reminders, initial: true) { _, plan in
            // The track moved (a new day, a module sent, the review unlocked): the day's reminders follow.
            let notifications = dependencies.notifications, wearables = dependencies.wearables
            Task { await notifications.updateTrack(plan, wearables: wearables) }
        }
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
            Task { await habits.load(patientId: patientId, day: today.day); await habits.loadNextCall() }
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
                    FoundationTrackCard { questionnaire = TrackQuestionnaireRef(id: $0) }
                    HealthPlanCard()
                    PlanTodayCard()

                    HStack(spacing: 12) {
                        Button { capture.openPhotoChooser() } label: {
                            MealScanCard()
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(1, contentMode: .fit)

                        EveningCheckinCard(today: content.today, now: dependencies.checkins.currentSlot)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .frame(maxHeight: 230)

                    if content.today.checkin?.redFlags.any == true {
                        RedFlagSignpostCard()
                    }

                    ProtocolReviewCard()
                    MessagesCard(unread: content.today.unreadClinicianMessages)
                }
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable {
                await model.load(refresh: true)
                await dependencies.track.load()
            }
        }
    }
}
