import SwiftUI

/// How the fortnight lands on Home. Four states, and only one of them is loud.
///
/// There is no streak, no score and no congratulation anywhere in here. The member
/// is lending us fourteen mornings; the app's job is to ask once, clearly, and
/// then get out of the way.

/// A. Nothing running — the quiet invitation. Note what it leads with: you do not
/// need a problem. That is the whole point of the optimisation door.
struct SleepTrackInviteCard: View {
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FAColor.forestSoft)
                            .frame(width: 38, height: 38)
                            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "sleepTrack.invite.title", defaultValue: "Understand your sleep"))
                                .font(FATypography.sans(15.5, .semibold, relativeTo: .headline))
                                .foregroundStyle(FAColor.ink)
                            Text(String(localized: "sleepTrack.invite.sub", defaultValue: "14 mornings · about 90 seconds each"))
                                .font(FATypography.caption)
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    }
                    Divider().overlay(FAColor.separator)
                    Text(String(localized: "sleepTrack.invite.noProblem", defaultValue: "You don’t need a problem to do this. Most people run it simply to see what their sleep actually looks like."))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// B. Running, this morning still open. The only card allowed to feel urgent.
struct SleepTrackMorningCard: View {
    let track: SleepTrack
    var watchSynced: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(FAColor.forest, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "sleepTrack.morningCard.title", defaultValue: "Last night, in 90 seconds"))
                                .font(FATypography.sans(15.5, .semibold, relativeTo: .headline))
                                .foregroundStyle(FAColor.ink)
                            Text(String(localized: "sleepTrack.morningCard.sub", defaultValue: "Night \(track.currentNight) of \(track.totalNights) · best done now"))
                                .font(FATypography.caption)
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forest)
                    }
                    NightDots(track: track)
                    if watchSynced {
                        HStack(spacing: 8) {
                            Image(systemName: "applewatch").font(.system(size: 12)).foregroundStyle(FAColor.inkSecondary).accessibilityHidden(true)
                            Text(String(localized: "sleepTrack.morningCard.watch", defaultValue: "Your watch has already sent its part. It can’t tell us your times, or how it felt."))
                                .font(FATypography.caption)
                                .foregroundStyle(FAColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11)
                        .modifier(FAGlassSurface(cornerRadius: FACornerRadius.sm, inset: true))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// C. Logged. Quiet on purpose — and it says why there is nothing to read.
struct SleepTrackLoggedCard: View {
    let track: SleepTrack
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FAColor.forestSoft)
                            .frame(width: 38, height: 38)
                            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "sleepTrack.logged.title", defaultValue: "Logged"))
                                .font(FATypography.sans(15.5, .semibold, relativeTo: .headline))
                                .foregroundStyle(FAColor.ink)
                            Text(String(localized: "sleepTrack.logged.sub", defaultValue: "Night \(track.currentNight) of \(track.totalNights) · \(track.totalNights - track.currentNight) to go"))
                                .font(FATypography.caption)
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    }
                    NightDots(track: track)
                    Text(String(localized: "sleepTrack.logged.nothingYet", defaultValue: "Nothing to read yet, on purpose. We look at the whole fortnight at once — a pattern read six nights in is mostly noise."))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// D. A morning was missed and is still inside its 48-hour window. Framed as a
/// night worth rescuing, never as a failure — and honest that a recalled night
/// counts for less.
struct SleepTrackBackfillCard: View {
    let dayLabel: String
    var onTap: () -> Void = {}

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(FAColor.warning)
                        .accessibilityHidden(true)
                    Text(String(localized: "sleepTrack.backfill.title", defaultValue: "\(dayLabel) morning is still open"))
                        .font(FATypography.sans(14.5, .semibold, relativeTo: .headline))
                        .foregroundStyle(FAColor.ink)
                }
                Text(String(localized: "sleepTrack.backfill.body", defaultValue: "You can still fill it in until tonight. We’ll mark it as recalled later, which makes it count for a little less — that is still much better than losing the night."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onTap) {
                    Text(String(localized: "sleepTrack.backfill.cta", defaultValue: "Fill in \(dayLabel)"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(FAColor.brand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(FAColor.brand, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Nights logged, as dots. A count, never a streak and never a score — a gap is
/// information, not a broken chain.
struct NightDots: View {
    let track: SleepTrack

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<track.totalNights, id: \.self) { i in
                Circle()
                    .fill(isLogged(i) ? FAColor.forestSoft : FAColor.inkMuted.opacity(0.28))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "sleepTrack.dots.a11y", defaultValue: "\(track.loggedCount) of \(track.totalNights) mornings logged"))
    }

    private func isLogged(_ index: Int) -> Bool {
        guard index < track.nights.count else { return false }
        return track.nights[index].isLogged
    }
}
