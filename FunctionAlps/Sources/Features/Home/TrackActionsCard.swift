import SwiftUI

/// "Your actions" on Home while the member is on the Foundation Track (Thomas, 2026-11-07): the habits by moment of the
/// day — Morning, Midday, Afternoon, Evening — one moment's pack at a time, at most three habits, the next ones once
/// those are done, then the next moment. Each row carries its streak with a little flame; a tap opens it a little
/// (its mini description and "See the habit"), and the mark ticks it as it always did (`TrackService.toggle`).
///
/// Every word of a habit is the practice's (`track_day.actions`, `habit_bank`); the card adds the layout and the moment's
/// name only. States (rule 5): the first read in flight holds no place (a member not on the track must see nothing);
/// a failed content read says so with a retry; a day without actions says so plainly. The unauthorized case is the
/// service's: it signs the member out (`TrackService.report`).
struct TrackActionsCard: View {
    @Environment(AppDependencies.self) private var dependencies
    /// A moment the member tapped; nil = the one the clock and the ticks choose.
    @State private var chosen: DayMoment?
    @State private var expanded: String?
    @State private var shown = false

    var body: some View {
        let track = dependencies.track
        Group {
            if let error = track.contentError, track.today == nil {
                FACard {
                    FAErrorState(title: String(localized: "habit.card.error", defaultValue: "Couldn't load your actions"), message: error) {
                        Task { await track.retry() }
                    }
                }
            } else if let day = track.today {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(day: day, now: context.date)
                }
            }
        }
        #if DEBUG
        .onAppear {
            guard !shown else { return }
            shown = true
            expanded = ShowcaseHabits.expandedKey
        }
        #endif
    }

    @ViewBuilder
    private func content(day: TrackDay, now: Date) -> some View {
        let track = dependencies.track
        let actions = day.actions
        var hour = Calendar.current.component(.hour, from: now)
        #if DEBUG
        hour = ShowcaseHabits.hourOverride ?? hour   // the showcase frames midday, where the pack is fullest
        #endif
        let auto = HabitPack.selectedMoment(hour: hour, actions: actions, isDone: track.isDone)
        let moment = chosen ?? auto
        let ordered = HabitPack.actions(actions, in: moment)
        let pack = HabitPack.visible(ordered, isDone: track.isDone)
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "habit.card.title", defaultValue: "Your actions"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                    .accessibilityAddTraits(.isHeader)
                if actions.isEmpty {
                    FAEmptyState(title: String(localized: "habit.card.empty", defaultValue: "No actions today"),
                                 message: String(localized: "habit.card.emptyMessage", defaultValue: "Your next ones appear here."))
                } else {
                    segments(actions, selected: moment, auto: auto)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(pack.shown) { action in
                            TrackHabitRow(day: day.day, action: action, expanded: expanded == action.key) {
                                withAnimation(.easeInOut(duration: 0.2)) { expanded = expanded == action.key ? nil : action.key }
                            }
                        }
                    }
                    if pack.more > 0 {
                        Text(String(localized: "habit.card.more", defaultValue: "\(pack.more) more once these are done"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    } else if !ordered.isEmpty, ordered.allSatisfy(track.isDone) {
                        Text(String(localized: "routine.allDone", defaultValue: "All done ✓"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }

    private func segments(_ actions: [TrackAction], selected: DayMoment, auto: DayMoment) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(HabitPack.segments(actions)) { segment in
                let on = segment.moment == selected
                Button {
                    chosen = segment.moment == auto ? nil : segment.moment
                    expanded = nil
                } label: {
                    HStack(spacing: 5) {
                        Text(segment.moment.label)
                        Text("\(segment.count)").font(FATypography.label).opacity(0.7)
                    }
                    .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(on ? FAColor.cream : Color(hex: 0x4A4A42))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(on ? FAColor.forest : Color.white.opacity(0.66), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "habit.segment.a11y", defaultValue: "\(segment.moment.label), \(segment.count) actions"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// One habit of the card: the mark ticks, the flame carries the streak, the title opens the row a little.
private struct TrackHabitRow: View {
    @Environment(AppDependencies.self) private var dependencies
    let day: Int
    let action: TrackAction
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        let track = dependencies.track
        let card = action.habitBankId.flatMap { track.cards[$0] }
        let title = TrackLogic.actionTitle(action, card: card, locale: track.locale)
        let done = track.isDone(action)
        let streak = TrackHabits.streak(key: action.key, days: track.days, activity: track.activity, today: day)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    Task { await track.toggle(action) }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(done ? FAColor.accent : FAColor.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done
                    ? String(localized: "plan.a11y.done", defaultValue: "Done: \(title)")
                    : String(localized: "plan.a11y.markDone", defaultValue: "Mark as done: \(title)"))
                .accessibilityAddTraits(done ? .isSelected : [])

                Button(action: onToggle) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HabitFlame(streak: streak)
                        Text(title)
                            .font(FATypography.callout)
                            .strikethrough(done)
                            .foregroundStyle(done ? FAColor.inkSecondary : FAColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if action.isNew {
                            Text(String(localized: "track.card.new", defaultValue: "New"))
                                .font(FATypography.label).foregroundStyle(FAColor.forestDark)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(FAColor.forestSoft.opacity(0.18), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded
                    ? String(localized: "habit.row.a11y.close", defaultValue: "Hides the description")
                    : String(localized: "habit.row.a11y.open", defaultValue: "Shows the description"))
                .accessibilityAddTraits(.isButton)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let text = TrackHabits.summary(action: action, card: card, locale: track.locale) {
                        Text(text).font(FATypography.callout).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink(value: Route.habit(action.key)) {
                        Text(String(localized: "habit.row.see", defaultValue: "See the habit ›"))
                            .font(FATypography.sans(13.5, .semibold, relativeTo: .callout)).foregroundStyle(FAColor.forest)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FAColor.forestSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.leading, 50)
                .transition(.opacity)
            }
        }
    }
}

/// The little flame and the days in a row. Drawn empty (no number) before the first one — never a "lost" streak; the
/// number says it, not the colour (rule 10).
struct HabitFlame: View {
    let streak: Int

    var body: some View {
        let lit = streak >= 1
        HStack(spacing: 2) {
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

/// The card's small lookups, kept out of the views.
enum TrackHabits {
    static func streak(key: String, days: [TrackDay], activity: Set<TrackActivityItem>, today: Int) -> Int {
        guard let span = HabitStreak.span(of: key, in: days) else { return 0 }
        return HabitStreak.current(done: HabitStreak.doneDays(key: key, activity: activity), first: span.first,
                                   last: span.last >= 14 ? nil : span.last, today: today)
    }

    /// The mini description: the card's, else the day's one-line how-to.
    static func summary(action: TrackAction, card: ActionCardRow?, locale: String) -> String? {
        card.flatMap { ActionCardLogic.pick($0.description, $0.descriptionFr, locale: locale) } ?? TrackLogic.text(action.howEn, action.howFr, locale: locale)
    }
}
