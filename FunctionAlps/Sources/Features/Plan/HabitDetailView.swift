import SwiftUI

/// The focus and action detail pages (mockups `iOSFocusDetail`, `iOSActionDetail`, decisions 2026-11-12): what it is,
/// how to do it, why it matters for this member, this week's ticks, the links to read or watch, and a "Done today"
/// button. The action page also shows its ladder level and "Try the next level" (`member_level_up`, through the habits
/// service). Every line is the member's own data or the practice's words; an empty section says so instead of inventing.
struct HabitDetailView: View {
    enum Kind: Hashable { case focus, action }

    @Environment(AppDependencies.self) private var dependencies
    let habitId: String
    let kind: Kind
    @State private var levelNote: String?

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: kind == .focus
                           ? String(localized: "focus.title", defaultValue: "This week's focus")
                           : String(localized: "action.title", defaultValue: "Action"),
                           hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if kind == .action { await dependencies.habits.loadLadders() }
        }
    }

    @ViewBuilder
    private var content: some View {
        let habits = dependencies.habits
        switch habits.phase {
        case .idle, .loading:
            FALoadingState(message: String(localized: "careplan.loading", defaultValue: "Loading your plan…"))
        case .failed(let message):
            FAErrorState(title: String(localized: "plan.failed.title", defaultValue: "Your plan did not load"), message: message) {
                Task { await habits.retry() }
            }
        case .loaded(let plan):
            if let habit = plan.habits.first(where: { $0.id == habitId }) {
                detail(habit, plan: plan)
            } else {
                FAEmptyState(title: String(localized: "habit.gone.title", defaultValue: "This is no longer in your plan"),
                             message: String(localized: "habit.gone.hint", defaultValue: "Go back to your plan to see what is current."))
            }
        }
    }

    @ViewBuilder
    private func detail(_ habit: HabitRow, plan: HabitPlan) -> some View {
        let habits = dependencies.habits
        let ticks = PlanScreensLogic.weekTicks(habitId: habit.id, completions: plan.completions, today: plan.day)
        let streak = HabitEngine.currentStreak(habit, completions: plan.completions, today: plan.day)
        let action = habits.actions(band: dependencies.focus.focus?.readiness?.bandValue).first { $0.id == habit.id }

        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Text(habit.title).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if streak >= 2 {
                    Text(String(localized: "clientplan.streak", defaultValue: "\(streak)-day streak"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                Text(String(localized: "habit.weekCount", defaultValue: "\(PlanScreensLogic.doneCount(ticks)) of 7 days this week"))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
        }

        if let action {
            FAButton(title: String(localized: "habit.doneToday", defaultValue: "Done today"),
                     style: action.done ? .secondary : .primary) {
                Task { await habits.toggle(action) }
            }
        }

        textCard(String(localized: "habit.whatItIs", defaultValue: "What it is"),
                 text: habit.description,
                 empty: String(localized: "habit.noDescription", defaultValue: "Your practitioner has not written this out yet."))

        textCard(String(localized: "habit.why", defaultValue: "Why it matters for you"),
                 text: PlanScreensLogic.why(habit),
                 empty: String(localized: "habit.noWhy", defaultValue: "Nothing written here yet."))

        weekCard(ticks)

        if kind == .action { levelCard(habit) }

        resourcesCard(habit)
    }

    private func textCard(_ label: String, text: String?, empty: String) -> some View {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return FACard {
            VStack(alignment: .leading, spacing: 8) {
                CPLabel(label)
                Text(value.isEmpty ? empty : value)
                    .font(FATypography.sans(14, relativeTo: .body))
                    .foregroundStyle(value.isEmpty ? FAColor.inkSecondary : FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weekCard(_ ticks: [PlanScreensLogic.WeekTick]) -> some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return FACard {
            VStack(alignment: .leading, spacing: 10) {
                CPLabel(String(localized: "habit.thisWeek", defaultValue: "This week"))
                HStack(spacing: 0) {
                    ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                        VStack(spacing: 4) {
                            Text(letters[index]).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                            Image(systemName: tick.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(tick.done ? FAColor.accent : FAColor.inkMuted)
                                .accessibilityLabel(tick.done ? String(localized: "habit.tick.done", defaultValue: "done") : String(localized: "habit.tick.notDone", defaultValue: "not done"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func levelCard(_ habit: HabitRow) -> some View {
        let habits = dependencies.habits
        if let ladder = habits.ladder(for: habit) {
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "habit.level", defaultValue: "Your level"))
                    Text(String(localized: "ladder.level", defaultValue: "Level \(ladder.number) of \(ladder.count)"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    Text(ladder.current.title).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    if ladder.next != nil {
                        FAButton(title: String(localized: "ladder.tryNext", defaultValue: "Try the next level"), style: .secondary) {
                            Task { await tryNext(habit) }
                        }
                        Text(String(localized: "ladder.next", defaultValue: "Next: \(ladder.next?.title ?? "")"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    } else if ladder.hiddenNext {
                        Text(String(localized: "ladder.comingSoon", defaultValue: "The next level is coming soon."))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                    if let levelNote {
                        Text(levelNote).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }

    private func tryNext(_ habit: HabitRow) async {
        let refusal = await dependencies.habits.levelUp(habit)
        switch refusal {
        case nil: levelNote = String(localized: "ladder.moved", defaultValue: "New level. Your streak carries on.")
        case .notReady?: levelNote = String(localized: "ladder.refused.notReady", defaultValue: "Not open yet: \(LadderLogic.completionsToLevelUp) times in 7 days at this level first.")
        case .oneChangePerWeek?: levelNote = String(localized: "ladder.refused.week", defaultValue: "One change per routine per week: this one opens a little later.")
        case .locked?: levelNote = String(localized: "ladder.locked", defaultValue: "Your practitioner keeps this level for now.")
        case .unavailable?: levelNote = String(localized: "ladder.refused.unavailable", defaultValue: "This next level isn't available to you yet.")
        case .failed?: levelNote = String(localized: "bank.writeFailed", defaultValue: "Your plan could not be updated. Please try again.")
        }
    }

    @ViewBuilder
    private func resourcesCard(_ habit: HabitRow) -> some View {
        let links = PlanScreensLogic.links(habit)
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                CPLabel(String(localized: "habit.resources", defaultValue: "Read and watch"))
                if links.isEmpty {
                    Text(String(localized: "habit.noResources", defaultValue: "No links for this yet."))
                        .font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
                } else {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, entry in
                        if let url = PlanScreensLogic.webURL(entry.url) {
                            Link(destination: url) {
                                HStack(spacing: 8) {
                                    Text((entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.forestDark)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.right.square").font(.system(size: 13)).foregroundStyle(FAColor.forestDark)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
        }
    }
}
