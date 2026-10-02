import SwiftUI

/// "My health plan" — the top of Home (owner, 2026-09-30): where the member stands in their care, before
/// anything to do. The clinician's words only: the plan's objective line and goals, the phase this week falls
/// in, and the items the clinician flagged as this week's focus as the priorities. Nothing is computed from
/// health data. The whole card opens the full plan.
///
/// States (rule 5): loading → a quiet line; failed → retry; no active plan → the plan's place blurred behind "Book your
/// call" (or the booked call's date); loaded → the plan. Shares the Habit Loop's read (`HabitsService`) with today's actions below it.
struct HealthPlanCard: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let habits = dependencies.habits
        switch habits.phase {
        case .idle, .loading:
            shell {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "careplan.loading", defaultValue: "Loading your plan…"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        case .failed(let message):
            FACard {
                FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"),
                             message: message) { Task { await habits.retry() } }
            }
        case .loaded(let plan):
            if plan.header == nil {
                // No plan yet (owner, 2026-10-02): the plan's place, blurred, behind "Book your call" — or the date
                // of the call already booked.
                shell {
                    PlanLockedArea(reason: .awaitingCall(habits.nextCall)) {
                        PlanPlaceholderLines(lines: 3, chips: true)
                    }
                }
            } else {
                NavigationLink(value: Route.carePlan) { loaded(plan) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func loaded(_ plan: HabitPlan) -> some View {
        let objective = plan.header?.objectiveLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goals = Array(plan.goals.prefix(3))
        let priorities = Array(plan.priorities.prefix(4))
        return shell(chevron: true, subtitle: phaseLine(plan)) {
            VStack(alignment: .leading, spacing: 12) {
                if !objective.isEmpty {
                    Text(objective)
                        .font(FATypography.display(17, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !goals.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        label(String(localized: "home.healthPlan.objectives", defaultValue: "Objectives"))
                        ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "target").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.forestSoft).accessibilityHidden(true)
                                Text(goal).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !priorities.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        label(String(localized: "home.healthPlan.priorities", defaultValue: "Priorities"))
                        FlowLayout(spacing: 6) {
                            ForEach(Array(priorities.enumerated()), id: \.offset) { _, priority in
                                Text(priority)
                                    .font(FATypography.sans(12, .medium, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(FAColor.forestSoft.opacity(0.16), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "home.healthPlan.hint", defaultValue: "Opens your full plan"))
    }

    /// "Phase title · Week 5", or "Week 5" without phases; nil before the plan starts or without a start date.
    private func phaseLine(_ plan: HabitPlan) -> String? {
        guard let week = HabitEngine.planWeek(start: plan.header?.startDate, today: plan.day) else { return nil }
        if let phase = HabitEngine.currentPhase(plan.phases, start: plan.header?.startDate, today: plan.day)?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines), !phase.isEmpty {
            return String(localized: "home.healthPlan.phaseWeek", defaultValue: "\(phase) · Week \(week)")
        }
        return String(localized: "home.healthPlan.week", defaultValue: "Week \(week)")
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
    }

    /// The card frame: the plan's icon, "My health plan", an optional phase line, then the content.
    private func shell<Content: View>(chevron: Bool = false, subtitle: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "leaf").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                        .frame(width: 40, height: 40)
                        .background(FAColor.forestSoft.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "home.healthPlan.title", defaultValue: "My health plan"))
                            .font(FATypography.headline).foregroundStyle(FAColor.ink)
                        if let subtitle {
                            Text(subtitle).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if chevron {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                            .accessibilityHidden(true)
                    }
                }
                content()
            }
        }
    }
}
