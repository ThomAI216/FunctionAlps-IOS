import SwiftUI

/// Starting a fortnight. One machine, two doors.
///
/// A member with a complaint and a member who is simply curious run the same
/// fourteen nights, the same diary and — this is the clinical point — the same
/// safety screen. Only the framing of the opening question and the shape of the
/// closing report differ.
struct SleepTrackStartView: View {
    @Environment(\.dismiss) private var dismiss
    var onChoose: (SleepTrackIntent) -> Void = { _ in }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                doors
                safetyNote
                whatItAsks
                pillars
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { dismiss() } label: {
                Text("‹ " + String(localized: "sleepTrack.back", defaultValue: "Back"))
                    .font(FATypography.sans(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(FAColor.ink)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Text(String(localized: "sleepTrack.start.title", defaultValue: "Fourteen nights"))
                .font(FATypography.display(26, relativeTo: .title))
                .foregroundStyle(FAColor.ink)
            Text(String(localized: "sleepTrack.start.intro", defaultValue: "A fortnight of ninety-second mornings, with your watch filling in the rest. We change nothing while it runs — the whole point is to see your real pattern before anyone suggests altering it."))
                .font(FATypography.sans(13, relativeTo: .subheadline))
                .foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var doors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "sleepTrack.start.which", defaultValue: "Which of these is you?").uppercased())
                .font(FATypography.label).tracking(0.8).foregroundStyle(FAColor.brand)

            door(
                intent: .focus,
                title: String(localized: "sleepTrack.door.focus.title", defaultValue: "Something about my sleep bothers me"),
                blurb: String(localized: "sleepTrack.door.focus.blurb", defaultValue: "You have a complaint you could name — falling asleep, staying asleep, waking too early, never feeling restored."),
                bullets: [
                    String(localized: "sleepTrack.door.focus.b1", defaultValue: "A longer set of questions first, focused on what you described"),
                    String(localized: "sleepTrack.door.focus.b2", defaultValue: "At the end: what seems to matter most, and one thing to try"),
                ]
            )

            door(
                intent: .baseline,
                title: String(localized: "sleepTrack.door.baseline.title", defaultValue: "Nothing’s wrong — I want to understand it"),
                blurb: String(localized: "sleepTrack.door.baseline.blurb", defaultValue: "Your sleep is fine as far as you know. You want to see what it actually looks like, and where the room is."),
                bullets: [
                    String(localized: "sleepTrack.door.baseline.b1", defaultValue: "A shorter set of questions — we skip what you have no complaint about"),
                    String(localized: "sleepTrack.door.baseline.b2", defaultValue: "At the end: what your pattern is, what is already steady, and where there is room"),
                    String(localized: "sleepTrack.door.baseline.b3", defaultValue: "The deeper questions come after, and only for whatever the fortnight actually turned up"),
                ]
            )
        }
    }

    private func door(intent: SleepTrackIntent, title: String, blurb: String, bullets: [String]) -> some View {
        Button { onChoose(intent) } label: {
            FACard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(title)
                            .font(FATypography.sans(16, .semibold, relativeTo: .headline))
                            .foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    Text(blurb)
                        .font(FATypography.sans(13, relativeTo: .subheadline))
                        .foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(bullets, id: \.self) { b in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•").font(FATypography.callout).foregroundStyle(FAColor.forestSoft)
                                Text(b).font(FATypography.callout).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Not a footnote. The asymptomatic member is precisely the one who would
    /// never have booked an appointment about their sleep — so the optimisation
    /// door is the only route by which they are ever screened.
    private var safetyNote: some View {
        FACard {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(FAColor.forestSoft)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(String(localized: "sleepTrack.safety.title", defaultValue: "The safety questions are the same either way"))
                        .font(FATypography.sans(14, .semibold, relativeTo: .headline))
                        .foregroundStyle(FAColor.ink)
                    Text(String(localized: "sleepTrack.safety.body", defaultValue: "Breathing during sleep, restless legs, unusual events at night, daytime sleepiness at the wheel. These are asked whether or not you have a complaint — because the people who most need them asked are usually the ones who would never have booked an appointment about their sleep."))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "sleepTrack.safety.body2", defaultValue: "If any of them turns something up, it goes to your practitioner as its own thing. It does not get folded into “areas to improve”."))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var whatItAsks: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "sleepTrack.asks.title", defaultValue: "What it asks of you").uppercased())
                    .font(FATypography.label).tracking(0.8).foregroundStyle(FAColor.brand)
                ask(1, String(localized: "sleepTrack.asks.1.t", defaultValue: "14 mornings"), String(localized: "sleepTrack.asks.1.b", defaultValue: "60–90 seconds each, best done before you are properly up"))
                ask(2, String(localized: "sleepTrack.asks.2.t", defaultValue: "Your watch, if you have one"), String(localized: "sleepTrack.asks.2.b", defaultValue: "It covers duration and physiology. It cannot cover when you got into bed, or how the night felt — that is why the morning log exists"))
                ask(3, String(localized: "sleepTrack.asks.3.t", defaultValue: "Nothing else to change"), String(localized: "sleepTrack.asks.3.b", defaultValue: "Live exactly as you normally would. A tidied-up fortnight tells us nothing"))
                Divider().overlay(FAColor.separator)
                Text(String(localized: "sleepTrack.asks.short", defaultValue: "If a few mornings slip, we will say so and offer to make it a one-week look instead. That is a real option, not a failure — but it is one we offer once you are in it, not a smaller thing to pick now."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ask(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                .foregroundStyle(FAColor.brand)
                .frame(width: 24, height: 24)
                .background(FAColor.forestGlow, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FATypography.sans(14, .medium, relativeTo: .body)).foregroundStyle(FAColor.ink)
                Text(body).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pillars: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "sleepTrack.pillars.title", defaultValue: "The same fortnight, for each pillar").uppercased())
                    .font(FATypography.label).tracking(0.8).foregroundStyle(FAColor.brand)
                pillarRow("moon.stars.fill", String(localized: "pillar.sleep", defaultValue: "Sleep"), String(localized: "pillar.ready", defaultValue: "Ready"), live: true)
                Divider().overlay(FAColor.separator)
                pillarRow("leaf.fill", String(localized: "pillar.nutrition", defaultValue: "Nutrition"), String(localized: "pillar.next", defaultValue: "Next"), live: false)
                Divider().overlay(FAColor.separator)
                pillarRow("brain.head.profile", String(localized: "pillar.stress", defaultValue: "Stress & recovery"), String(localized: "pillar.after", defaultValue: "After that"), live: false)
                Divider().overlay(FAColor.separator)
                pillarRow("figure.run", String(localized: "pillar.movement", defaultValue: "Movement"), String(localized: "pillar.last", defaultValue: "Last"), live: false)
                Text(String(localized: "sleepTrack.pillars.note", defaultValue: "Each one works the same way, and each can be run either because something is wrong or simply to see where you stand. One at a time — running two fortnights at once would tell you less, not more."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func pillarRow(_ symbol: String, _ name: String, _ when: String, live: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(live ? FAColor.forestSoft : FAColor.inkMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(name)
                .font(FATypography.sans(14.5, live ? .medium : .regular, relativeTo: .body))
                .foregroundStyle(live ? FAColor.ink : FAColor.inkMuted)
            Spacer(minLength: 0)
            Text(when)
                .font(FATypography.label)
                .foregroundStyle(live ? FAColor.forestSoft : FAColor.inkMuted)
        }
        .padding(.vertical, 2)
    }
}
