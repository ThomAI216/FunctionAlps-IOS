import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: HomeViewModel?

    var body: some View {
        ZStack {
            FAColor.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .navigationTitle(String(localized: "tab.today", defaultValue: "Today"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = HomeViewModel(members: dependencies.members, dashboard: dependencies.dashboard, auth: dependencies.auth)
                model = m
                await m.load()
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
            ScrollView {
                VStack(alignment: .leading, spacing: FASpacing.lg) {
                    header(model, content.member)
                    checkinCard(content.today)
                    mealsSection(content.today, profile: content.member.profile)
                    if content.today.unreadClinicianMessages > 0 {
                        messagesCard(content.today.unreadClinicianMessages)
                    }
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load(refresh: true) }
        }
    }

    private func header(_ model: HomeViewModel, _ member: Member) -> some View {
        VStack(alignment: .leading, spacing: FASpacing.xs) {
            Text(model.greeting)
                .font(FATypography.label)
                .foregroundStyle(FAColor.accent)
                .tracking(0.8)
            Text(member.firstName)
                .font(FATypography.largeTitle)
                .foregroundStyle(FAColor.ink)
        }
        .padding(.top, FASpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func checkinCard(_ today: TodaySnapshot) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                Text(String(localized: "home.checkin.title", defaultValue: "Daily check-in"))
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
                if let checkin = today.checkin, checkin.isFunctionalDone {
                    Label(String(localized: "home.checkin.done", defaultValue: "Done for today"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FAColor.success)
                        .font(FATypography.callout)
                    HStack(spacing: FASpacing.md) {
                        marker(String(localized: "marker.energy", defaultValue: "Energy"), checkin.energy)
                        marker(String(localized: "marker.mood", defaultValue: "Mood"), checkin.mood)
                        marker(String(localized: "marker.sleep", defaultValue: "Sleep"), checkin.sleep)
                        marker(String(localized: "marker.calm", defaultValue: "Calm"), checkin.calmness)
                    }
                } else {
                    Label(String(localized: "home.checkin.pending", defaultValue: "Not yet today — check-ins arrive in the next release"), systemImage: "circle.dashed")
                        .foregroundStyle(FAColor.inkSecondary)
                        .font(FATypography.callout)
                }
            }
        }
    }

    private func marker(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value.map(String.init) ?? "–")
                .font(FATypography.metric)
                .foregroundStyle(FAColor.ink)
            Text(label)
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value.map(String.init) ?? String(localized: "marker.none", defaultValue: "not recorded"))")
    }

    private func mealsSection(_ today: TodaySnapshot, profile: MemberProfile?) -> some View {
        FASection(title: String(localized: "home.meals.title", defaultValue: "Today's meals"), kicker: String(localized: "home.today", defaultValue: "Today")) {
            if today.meals.isEmpty {
                FACard {
                    FAEmptyState(
                        title: String(localized: "home.meals.empty.title", defaultValue: "Nothing logged yet"),
                        message: String(localized: "home.meals.empty.message", defaultValue: "Meals you log in FunctionAlps show up here."),
                        systemImage: "fork.knife"
                    )
                }
            } else {
                HStack(spacing: FASpacing.sm) {
                    FAMetricCard(label: String(localized: "macros.energy", defaultValue: "Energy"), value: Format.kcal(today.totalCalories), caption: profile?.targetCalories.map { String(localized: "macros.target", defaultValue: "of \($0) target") })
                    FAMetricCard(label: String(localized: "macros.protein", defaultValue: "Protein"), value: Format.grams(today.totalProteinG), caption: profile?.targetProteinG.map { String(localized: "macros.target", defaultValue: "of \($0) target") })
                }
                FACard {
                    VStack(spacing: 0) {
                        ForEach(today.meals) { meal in
                            mealRow(meal)
                            if meal.id != today.meals.last?.id { Divider().overlay(FAColor.separator) }
                        }
                    }
                }
            }
        }
    }

    private func mealRow(_ meal: MealLog) -> some View {
        let title = meal.name ?? meal.mealType?.localizedName ?? String(localized: "meal.type.other", defaultValue: "Meal")
        let subtitle: String = {
            switch meal.analysisStatus {
            case .queued, .pending, .analyzing: return String(localized: "meal.status.analyzing", defaultValue: "Analysing…")
            case .failed: return String(localized: "meal.status.failed", defaultValue: "Analysis failed")
            default:
                let kcal = meal.totalCalories.map(Format.kcal) ?? ""
                return [Format.time(meal.loggedAt), kcal].filter { !$0.isEmpty }.joined(separator: " · ")
            }
        }()
        return FAListRow(title: title, subtitle: subtitle, systemImage: meal.source == .photo ? "camera" : "text.alignleft")
    }

    private func messagesCard(_ count: Int) -> some View {
        FACard {
            FAListRow(
                title: String(localized: "home.messages.unread", defaultValue: "\(count) unread from your practitioner"),
                subtitle: String(localized: "home.messages.hint", defaultValue: "Read them in the FunctionAlps app for now"),
                systemImage: "envelope.badge"
            )
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppDependencies.preview())
}
