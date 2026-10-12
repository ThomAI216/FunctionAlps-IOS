import SwiftUI

/// The routine of the moment — the clinician's habits due today, checked off in place, right under "My health plan".
/// Home shows ONE routine (owner, 2026-10-06): the morning routine from 6:00 to 10:00, the day's actions until 18:00,
/// the evening routine after — up to the routine's cap (3 · 6 · 3); the plan page keeps the whole day. Every row
/// carries a flame with its streak.
///
/// The clinician decides, the software reveals: every row is a habit a practitioner authored and approved
/// (RLS on `habits` is the boundary); the card adds nothing but arithmetic — due today, done today, the run so
/// far. Done is said by the mark AND the strikethrough, never by colour alone (rule 10). The current moment's
/// actions lead; an earlier moment's skipped action is not carried (see `HabitEngine.todayActions`).
///
/// States (rule 5): while the first load is in flight the card holds no place — most members have no habits yet,
/// and a skeleton that vanishes on every launch would shove Home around for nothing; a member with no habits sees
/// the card's place blurred, with the foundation bank to start from (owner, 2026-10-02); a failed load says so,
/// with a retry; a refresh keeps the rows.
struct PlanTodayCard: View {
    @Environment(AppDependencies.self) private var dependencies
    /// Today's morning check-in is saved (Home's own snapshot, `CheckinEngine.slotIsDone`). The morning routine
    /// opens with it (owner, 2026-10-12): without a wearable, it is how the day gets its sleep and its focus.
    var morningCheckinDone = false

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
            if let routine = habits.routineNow(band: readiness?.bandValue),
               !plan.activeHabits.isEmpty || HabitEngine.showsMorningCheckin(routine.slot, hour: habits.hour, done: morningCheckinDone) {
                // The card shows for everyone while the morning check-in is on it, even before any action exists.
                card(plan, routine: routine, readiness: readiness, hour: habits.hour)
            } else {
                // No actions yet: the card's place, blurred, with the foundation bank as the way to start.
                FACard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "plan.today.title", defaultValue: "Today's actions")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                        PlanLockedArea(reason: .noActions) { PlanPlaceholderLines(lines: 4) }
                    }
                }
            }
        }
    }

    private func card(_ plan: HabitPlan, routine: HabitEngine.RoutineNow, readiness: FocusReadiness?, hour: Int) -> some View {
        let actions = routine.actions
        // The morning routine opens with the check-in; missed, it stays on the day's card until 17:00 (not counted there).
        let withCheckin = HabitEngine.showsMorningCheckin(routine.slot, hour: hour, done: morningCheckinDone)
        let count = HabitEngine.routineCount(routine, morningCheckinDone: morningCheckinDone)
        let remaining = count.total - count.done
        let headline = routine.slot.routineTitle
        // Nothing in this routine today (a weekly action on its off day, or a routine left empty): say so plainly.
        let subtitle = count.total == 0
            ? (withCheckin ? routine.slot.window : routine.slot.window + " · " + String(localized: "routine.empty", defaultValue: "Nothing in this routine today"))
            : remaining == 0
                ? routine.slot.window + " · " + String(localized: "routine.allDone", defaultValue: "All done ✓")
                : routine.slot.window + " · " + String(localized: "routine.progress", defaultValue: "\(count.done) of \(count.total) done")
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: routine.slot.symbol).font(.system(size: 19)).foregroundStyle(FAColor.accent)
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
                if withCheckin || !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if withCheckin { MorningCheckinLine(done: morningCheckinDone) }
                        ForEach(actions) { HabitLine(action: $0) }
                    }
                }
                if withCheckin && plan.activeHabits.isEmpty {
                    // No action yet: the morning still opens with the check-in; the bank is the way to a first action.
                    PlanLockedArea(reason: .noActions) { PlanPlaceholderLines(lines: 2) }
                }
                if routine.more > 0 {
                    NavigationLink(value: Route.carePlan) {
                        Text(String(localized: "routine.more", defaultValue: "\(routine.more) more in your plan ›"))
                            .font(FATypography.caption).foregroundStyle(FAColor.forest)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One habit of the day: the mark checks off in place, the title reads, the flame on the right carries the streak.
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

            // The rest of the row opens the action's card: how to do it, a demonstration, why, what to read.
            NavigationLink(value: Route.action(action.id)) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(FATypography.callout)
                            .strikethrough(action.done)
                            .foregroundStyle(action.done ? FAColor.inkSecondary : FAColor.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let meta {
                            Text(meta).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    StreakFlame(streak: action.streak)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "action.a11y.open", defaultValue: "Opens how to do it"))
        }
    }

    /// "Breathwork · 5 min" — the card's type and length, when the habit has a card.
    private var meta: String? {
        let parts = [action.cardKind?.label, action.durationMin.map { String(localized: "action.minutes", defaultValue: "\($0) min") }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The first row of the morning routine: today's morning check-in — last night, how you walk into the day, what
/// today is for, how you feel and why (owner, 2026-10-12). Not a habit: the mark says done or not, the whole row opens
/// the check-in (to fill it in, or to adjust it). Done is said by the mark AND the strikethrough (rule 10).
struct MorningCheckinLine: View {
    let done: Bool

    var body: some View {
        let title = String(localized: "home.carousel.morning", defaultValue: "Morning check-in")
        NavigationLink(value: Route.checkin(.morning)) {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? FAColor.accent : FAColor.inkMuted)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FATypography.callout)
                        .strikethrough(done)
                        .foregroundStyle(done ? FAColor.inkSecondary : FAColor.ink)
                    Text(done
                         ? String(localized: "home.carousel.done", defaultValue: "Done · tap to adjust")
                         : String(localized: "home.carousel.now", defaultValue: "It's time · about a minute"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done
            ? String(localized: "plan.a11y.done", defaultValue: "Done: \(title)")
            : title)
        .accessibilityHint(String(localized: "home.checkin.cta", defaultValue: "Check in"))
    }
}

/// The flame beside every action (owner, 2026-10-06): filled with the number of days in a row once there is one,
/// drawn empty before — never a "lost" streak. The number says it, not the colour (rule 10).
struct StreakFlame: View {
    let streak: Int

    var body: some View {
        let lit = streak >= HabitEngine.streakBadgeMin
        HStack(spacing: 3) {
            Image(systemName: lit ? "flame.fill" : "flame").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            if lit { Text("\(streak)").font(FATypography.label).monospacedDigit() }
        }
        .foregroundStyle(lit ? FAColor.streak : FAColor.inkMuted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lit
            ? String(localized: "plan.a11y.streak", defaultValue: "\(streak)-day streak")
            : String(localized: "plan.a11y.noStreak", defaultValue: "No streak yet"))
    }
}
