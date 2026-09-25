import SwiftUI

/// "Today from your plan" — the clinician's habits due today, checked off in place (the Expo `PlanTodayCard`).
///
/// The clinician decides, the software reveals: every row is a habit a practitioner authored and approved
/// (RLS on `habits` is the boundary); the card adds nothing but arithmetic — due today, done today, the run so
/// far. Done is said by the mark AND the strikethrough, never by colour alone (rule 10). The headline is the
/// clinician's objective when they wrote one; otherwise it describes the practice and never promises an outcome.
///
/// States (rule 5): while the first load is in flight the card holds no place — most members have no habits yet,
/// and a skeleton that vanishes on every launch would shove Home around for nothing; a member with no habits
/// sees no card (Today's focus sits right above); a failed load says so, with a retry; a refresh keeps the rows.
struct PlanTodayCard: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let habits = dependencies.habits
        switch habits.phase {
        case .idle, .loading:
            EmptyView()
        case .failed(let message):
            FACard {
                FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"),
                             message: message) { Task { await habits.retry() } }
            }
        case .loaded(let plan):
            // The day's band is the focus service's — one server read of the day, shared by the focus and the faces.
            let readiness = dependencies.focus.focus?.readiness
            if !plan.activeHabits.isEmpty {
                card(plan, actions: habits.actions(band: readiness?.bandValue), hour: habits.hour, readiness: readiness)
            }
        }
    }

    private func card(_ plan: HabitPlan, actions: [HabitAction], hour: Int, readiness: FocusReadiness?) -> some View {
        let remaining = actions.filter { !$0.done }.count
        let headline = HabitEngine.headline(plan)
        // Active habits, none due today (a weekly one on its off day): a rest day is not "all done".
        let subtitle = actions.isEmpty
            ? String(localized: "plan.nothingDue", defaultValue: "Nothing due today")
            : HabitEngine.subtitle(actions, hour: hour)
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "list.clipboard").font(.system(size: 19)).foregroundStyle(FAColor.accent)
                        .frame(width: 40, height: 40)
                        .background(FAColor.accent.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(FATypography.headline).foregroundStyle(FAColor.ink).lineLimit(2)
                        Text(subtitle).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if remaining > 0 {
                        Text("\(remaining)")
                            .font(FATypography.label).foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                            .background(FAColor.accent, in: Capsule())
                            .accessibilityLabel(String(localized: "plan.a11y.remaining", defaultValue: "\(remaining) to go"))
                    }
                }
                // The one sentence the card writes itself — the owner-approved case only (2026-09-25): a habit
                // made gentler because readiness is below the member's OWN baseline. A high day shows the further
                // face and says nothing; a gentler face on a self-reported low day says nothing either.
                if readiness?.bandValue == .low, readiness?.vsBaseline == true, actions.contains(where: { $0.face == .easy }) {
                    Text(String(localized: "focus.reason.readinessLow", defaultValue: "Your recovery is below your usual — an easier version today."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actions.prefix(HabitEngine.homeActionLimit)) { HabitLine(action: $0) }
                    }
                }
                NavigationLink(value: Route.carePlan) {
                    HStack(spacing: 3) {
                        Text(String(localized: "plan.open", defaultValue: "Open my plan"))
                            .font(FATypography.sans(12.5, .semibold, relativeTo: .caption))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(FAColor.accent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One habit of the day: the mark checks off in place, the title reads, the streak is a quiet fact on the right
/// (from two days up — one day in a row is a day, not a streak).
private struct HabitLine: View {
    @Environment(AppDependencies.self) private var dependencies
    let action: HabitAction

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let habits = dependencies.habits
                Task { await habits.toggle(action) }
            } label: {
                Image(systemName: action.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(action.done ? FAColor.accent : FAColor.inkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.done
                ? String(localized: "plan.a11y.done", defaultValue: "Done: \(action.title)")
                : String(localized: "plan.a11y.markDone", defaultValue: "Mark as done: \(action.title)"))
            .accessibilityAddTraits(action.done ? .isSelected : [])

            Text(action.title)
                .font(FATypography.callout)
                .strikethrough(action.done)
                .foregroundStyle(action.done ? FAColor.inkSecondary : FAColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if action.streak >= HabitEngine.streakBadgeMin {
                HStack(spacing: 3) {
                    Image(systemName: "flame").font(.system(size: 11)).accessibilityHidden(true)
                    Text("\(action.streak)").font(FATypography.label)
                }
                .foregroundStyle(FAColor.inkMuted)
                .accessibilityLabel(String(localized: "plan.a11y.streak", defaultValue: "\(action.streak)-day streak"))
            }
        }
    }
}
