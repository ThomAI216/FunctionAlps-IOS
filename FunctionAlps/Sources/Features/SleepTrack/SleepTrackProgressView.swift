import SwiftUI

/// Mid-fortnight. The hardest screen in the pillar, because the member wants an
/// answer and the honest thing is to refuse to give one yet (spec §3.5: at day 7
/// we check data quality and show no causal conclusions).
///
/// What it shows: counts. What it does not show: an average, a trend line, a
/// "your sleep so far" figure — anything a member could carry around for the rest
/// of the fortnight and start sleeping against.
struct SleepTrackProgressView: View {
    @Environment(\.dismiss) private var dismiss
    let track: SleepTrack
    var watchNights: Int = 0
    var onOfferShortProtocol: () -> Void = {}

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                progressCard
                withheldCard
                coverageCard
                if watchNights > 0 { watchCard }
                shortProtocolCard
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
            Text(String(localized: "sleepTrack.progress.title", defaultValue: "Where you are"))
                .font(FATypography.display(26, relativeTo: .title))
                .foregroundStyle(FAColor.ink)
        }
        .padding(.top, 6)
    }

    private var progressCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(track.currentNight)")
                        .font(FATypography.metric)
                        .foregroundStyle(FAColor.ink)
                    Text(String(localized: "sleepTrack.progress.ofNights", defaultValue: "of \(track.totalNights) nights"))
                        .font(FATypography.sans(14.5, relativeTo: .body))
                        .foregroundStyle(FAColor.inkSecondary)
                    Spacer(minLength: 0)
                    Text(String(localized: "sleepTrack.progress.logged", defaultValue: "\(track.loggedCount) logged"))
                        .font(FATypography.label)
                        .foregroundStyle(FAColor.forestSoft)
                }
                NightDots(track: track)
                Divider().overlay(FAColor.separator)
                Text(String(localized: "sleepTrack.progress.gaps", defaultValue: "Two mornings are missing. Neither is a problem on its own — the next few will make the whole fortnight a good deal more reliable, and both free days are still to come."))
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The refusal, stated as a reason rather than a rule.
    private var withheldCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(FAColor.inkMuted)
                        .accessibilityHidden(true)
                    Text(String(localized: "sleepTrack.withheld.title", defaultValue: "Nothing to read yet, and that is deliberate"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline))
                        .foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(String(localized: "sleepTrack.withheld.body", defaultValue: "We could show you an average tonight. It would be mostly noise — seven nights is not enough to tell a pattern from a bad week, and a number you see now would change how you sleep for the rest of the fortnight."))
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "sleepTrack.withheld.body2", defaultValue: "On the morning after night 14, all of it opens at once."))
                    .font(FATypography.callout)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Counts, not conclusions. The free-day line matters more than it looks: the
    /// working-vs-free difference is one of the few things a fortnight can show.
    private var coverageCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "sleepTrack.coverage.title", defaultValue: "What we have so far").uppercased())
                    .font(FATypography.label).tracking(0.8).foregroundStyle(FAColor.brand)
                coverageRow(String(localized: "sleepTrack.coverage.mornings", defaultValue: "Mornings logged"), "\(track.loggedCount) of \(track.currentNight)")
                Divider().overlay(FAColor.separator)
                coverageRow(String(localized: "sleepTrack.coverage.watch", defaultValue: "Nights from your watch"), "\(watchNights) of \(track.currentNight)")
                Divider().overlay(FAColor.separator)
                coverageRow(String(localized: "sleepTrack.coverage.free", defaultValue: "Free days covered"), String(localized: "sleepTrack.coverage.freeValue", defaultValue: "\(track.freeDaysCovered) — we need at least 2"))
                Text(String(localized: "sleepTrack.coverage.note", defaultValue: "Counts, not conclusions. The free-day one matters more than it looks: the difference between your working nights and your free ones is one of the few things a fortnight can actually show."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func coverageRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
            Spacer(minLength: 0)
            Text(value).font(FATypography.sans(13.5, .semibold, relativeTo: .callout)).foregroundStyle(FAColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var watchCard: some View {
        FACard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "applewatch")
                    .foregroundStyle(FAColor.inkSecondary)
                    .accessibilityHidden(true)
                Text(String(localized: "sleepTrack.progress.watch", defaultValue: "Your watch is syncing on its own — duration, heart rate, HRV and breathing. You do not need to do anything with it, and we will show you its numbers beside yours at the end, separately, even where they disagree."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The escape hatch, offered here rather than on the way in — where a tired
    /// member would simply have picked the smaller number.
    private var shortProtocolCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 9) {
                Text(String(localized: "sleepTrack.short.title", defaultValue: "Is fourteen mornings turning out to be a lot?"))
                    .font(FATypography.sans(14.5, .semibold, relativeTo: .headline))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "sleepTrack.short.body", defaultValue: "We can make this a one-week look instead and close it on Sunday. You would get a smaller, more cautious picture rather than no picture — and we would say plainly which parts we are less sure about."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onOfferShortProtocol) {
                    Text(String(localized: "sleepTrack.short.cta", defaultValue: "Tell me more about the shorter version"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(FAColor.brand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(FAColor.brand, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }
}
