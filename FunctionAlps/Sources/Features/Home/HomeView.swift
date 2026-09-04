import SwiftUI

/// The web app's Home, card for card: functional hero → the two action squares → messages.
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
            let notifications = dependencies.notifications, wearables = dependencies.wearables
            Task {
                await notifications.loadPrefs(patientId: patientId)
                await notifications.refreshAuthorization()
                await notifications.replan(snapshot: today, wearables: wearables)
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

                        NavigationLink(value: Route.checkin(dependencies.checkins.currentSlot)) {
                            CheckinPulseCard(markers: markers(content.today))
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .frame(maxHeight: 230)

                    momentsRow(content.today)

                    MessagesCard(unread: content.today.unreadClinicianMessages)
                }
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }

    /// mood · sleep · energy · calmness, each with its canonical accent (the check-in hub's).
    private func markers(_ today: TodaySnapshot) -> [CheckinPulseCard.Marker] {
        let c = today.checkin
        return [
            .init(key: "mood", name: String(localized: "marker.mood", defaultValue: "Mood"), color: Color(hex: 0xDB2777), value: c?.mood),
            .init(key: "sleep", name: String(localized: "marker.sleep", defaultValue: "Sleep"), color: Color(hex: 0x6366F1), value: c?.sleep),
            .init(key: "energy", name: String(localized: "marker.energy", defaultValue: "Energy"), color: Color(hex: 0xD97706), value: c?.energy),
            .init(key: "stress", name: String(localized: "marker.calm", defaultValue: "Calmness"), color: Color(hex: 0xE11D48), value: c?.calmness),
        ]
    }

    /// The day's three moments — the one "now" falls in is highlighted; saved ones re-open for editing.
    private func momentsRow(_ today: TodaySnapshot) -> some View {
        let now = dependencies.checkins.currentSlot
        return HStack(spacing: 8) {
            ForEach(MomentSlot.order, id: \.self) { slot in
                let done = CheckinEngine.slotIsDone(today.moments, slot)
                let isNow = slot == now
                let status: String = isNow
                    ? (done ? String(localized: "home.checkin.again", defaultValue: "✓ Check in again") : String(localized: "home.checkin.cta", defaultValue: "Check in"))
                    : (done ? String(localized: "home.checkin.done", defaultValue: "✓ Done") : String(localized: "home.checkin.open", defaultValue: "Open"))
                NavigationLink(value: Route.checkin(slot)) {
                    VStack(spacing: 3) {
                        Text(slot.glyph).font(.system(size: isNow ? 17 : 15)).foregroundStyle(isNow ? FAColor.accent : FAColor.inkSecondary)
                        Text(slot.localizedName).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                        Text(status).font(FATypography.sans(10.5, .medium, relativeTo: .caption2)).foregroundStyle(done || isNow ? FAColor.accent : FAColor.inkSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 6)
                    .background(isNow ? FAColor.accent.opacity(0.2) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isNow ? FAColor.accent : FAColor.separator, lineWidth: isNow ? 1.5 : 1))
                    .opacity(isNow ? 1 : 0.85)
                }
                .buttonStyle(.plain)
                .layoutPriority(isNow ? 1 : 0)
                .accessibilityLabel("\(slot.localizedName): \(status)")
            }
        }
    }
}
