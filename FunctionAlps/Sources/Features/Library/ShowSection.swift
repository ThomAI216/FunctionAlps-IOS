import SwiftUI

// The show inside the Library tab (approved mockup "iOS app — Library tab", 2026-10-03): the glass "next live" card
// under the title, "This week's episodes" (or, before any replay exists, the week as day tiles) as the first section,
// and the experiments in progress at the top of Continue. Same card family as the rest of the Library.

/// The show's cover: the topic cover of the track (`library_topic_covers`), else the topic gradient.
struct ShowCover: View {
    let track: ShowTrack?
    let covers: [String: URL]
    var height: CGFloat
    var badge: String? = nil

    var body: some View {
        let topic = ShowLogic.trackTopic(track)
        PillarCover(pillar: topic, height: height, badge: badge, badgeTone: .new, cover: covers[topic] ?? covers["foundations"])
    }
}

/// "LIVE TOMORROW · 12:30 — The week in review, your questions". Opens the website's events agenda (registration
/// and reminders live there).
struct ShowLiveCard: View {
    let snapshot: ShowSnapshot
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let live = snapshot.nextLive {
            Button { openURL(ShowLogic.eventsURL) } label: {
                FACard(padded: false) {
                    HStack(spacing: 14) {
                        VStack(spacing: 1) {
                            Text(ShowFormat.weekdayShort(live.start).uppercased())
                                .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(0.9)
                                .foregroundStyle(Color(hex: 0xE6C27A))
                            Text(ShowFormat.dayNumber(live.start))
                                .font(FATypography.display(18, relativeTo: .headline))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 50, height: 50)
                        .background(FAColor.forest, in: Circle())
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ShowFormat.liveLabel(live).uppercased())
                                .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1)
                                .foregroundStyle(FALibraryColor.gold)
                            Text(title(live))
                                .font(FATypography.display(16, relativeTo: .headline))
                                .foregroundStyle(FAColor.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subtitle(live))
                                .font(FATypography.sans(10.5, relativeTo: .caption))
                                .foregroundStyle(FAColor.inkSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FAColor.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(String(localized: "show.seeEvents", defaultValue: "See the events"))
        }
    }

    private func title(_ live: ShowSnapshot.Live) -> String {
        if snapshot.preLaunch {
            let date = ShowFormat.weekdayLong(ShowLogic.noon(ShowLogic.launchDay))
            return String(localized: "show.startsOn", defaultValue: "The show starts \(date)")
        }
        if let title = live.title?.pick(ShowFormat.lang), !title.isEmpty { return title }
        return String(localized: "show.liveDefaultTitle", defaultValue: "The week in review, and your questions")
    }

    private func subtitle(_ live: ShowSnapshot.Live) -> String {
        if snapshot.preLaunch {
            let time = ShowFormat.clock(live.start)
            return String(localized: "show.startsSub", defaultValue: "It opens with a live at \(time), then a new episode every day from Tuesday to Friday.")
        }
        return live.slug != nil
            ? String(localized: "show.remindTap", defaultValue: "Tap to get a reminder")
            : String(localized: "show.liveSub", defaultValue: "The week's episodes and members' questions, live.")
    }
}

/// A section title with its line underneath (the Library's serif head, the mockup's grey sub-line).
struct ShowSectionHead: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(FATypography.display(17, relativeTo: .headline)).foregroundStyle(FAColor.ink)
            if let subtitle {
                Text(subtitle).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 9)
    }
}

/// One replay: cover (+ TODAY), gold "Pillar · Ep. N", serif title, "31 min · 5 pieces".
struct ShowEpisodeTile: View {
    let episode: ShowEpisodeCard
    let isToday: Bool
    let covers: [String: URL]
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ShowCover(track: episode.track, covers: covers, height: 100,
                              badge: isToday ? String(localized: "show.today", defaultValue: "Today") : nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ShowFormat.eyebrow(kind: episode.kind, track: episode.track, number: episode.number).uppercased())
                            .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1)
                            .foregroundStyle(FALibraryColor.gold).lineLimit(1)
                        Text(episode.title.pick(ShowFormat.lang))
                            .font(FATypography.display(14.5, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                            .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                        Text(ShowFormat.cardMeta(episode))
                            .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                    }
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 236)
        .accessibilityElement(children: .combine)
    }
}

/// One day of the week before its replay exists: "Today" / "Tue 6 Oct", the pillar (or Live), then the title once
/// published, else "At 12:30".
struct ShowDayTile: View {
    let day: ShowSnapshot.WeekDay
    let onPress: (() -> Void)?

    var body: some View {
        Button { onPress?() } label: {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(day.isToday ? String(localized: "show.today", defaultValue: "Today") : ShowFormat.weekdayDayShort(day.start))
                        .font(FATypography.sans(10.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                    Text((day.kind == .live ? String(localized: "show.stripLive", defaultValue: "Live") : ShowFormat.trackLabel(day.track)).uppercased())
                        .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1)
                        .foregroundStyle(day.kind == .live ? FAColor.forest : FALibraryColor.gold)
                        .lineLimit(2)
                    if let title = day.episode?.title ?? day.upcoming?.title {
                        Text(title.pick(ShowFormat.lang))
                            .font(FATypography.display(13.5, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    } else {
                        let time = ShowFormat.clock(day.start)
                        Text(String(localized: "show.stripSoon", defaultValue: "At \(time)"))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 132, alignment: .topLeading)
                .frame(minHeight: 108, alignment: .topLeading)
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                            .strokeBorder(FALibraryColor.gold.opacity(0.6), lineWidth: 1.5)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onPress == nil)
        .accessibilityElement(children: .combine)
    }
}

/// An experiment in progress (Continue): cover thumb, "EXPERIMENT · MOVEMENT", "Day 3 of 7 · walk after lunch",
/// the seven-day bar, and the check that marks today done (once a day, in order — like the web).
struct ShowExperimentRowView: View {
    let row: ShowExperimentRow
    let covers: [String: URL]
    let marking: Bool
    let onOpen: () -> Void
    let onMark: () -> Void

    var body: some View {
        FACard(padded: false) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        ShowCover(track: row.card?.track, covers: covers, height: 54)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kicker.uppercased())
                                .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1)
                                .foregroundStyle(FALibraryColor.gold).lineLimit(1)
                            Text(line)
                                .font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            segments
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                markButton
            }
            .padding(12)
        }
    }

    private var kicker: String {
        "\(String(localized: "show.piece.experiment", defaultValue: "Experiment")) · \(ShowFormat.trackLabel(row.card?.track))"
    }

    private var line: String {
        let head = String(localized: "show.dayOfTotal", defaultValue: "Day \(row.current) of \(row.total)")
        if row.state.doneToday {
            return String(localized: "show.doneTodayShort", defaultValue: "\(head) · done for today")
        }
        guard let action = row.action else { return head }
        return "\(head) · \(action)"
    }

    private var segments: some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, row.total), id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for i: Int) -> Color {
        let dayNumbers = row.days.isEmpty ? Array(1...7) : row.days.map(\.day)
        let day = i - 1 < dayNumbers.count ? dayNumbers[i - 1] : i
        if row.state.done.contains(day) { return FAColor.forest }
        if day == row.state.nextDay && !row.state.doneToday { return FAColor.forestSoft }
        return Color.black.opacity(0.1)
    }

    @ViewBuilder
    private var markButton: some View {
        if row.canMarkToday || row.state.doneToday {
            Button(action: onMark) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(row.state.doneToday ? FAColor.forestSoft.opacity(0.55) : FAColor.forest, in: Circle())
                    .opacity(marking ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(!row.canMarkToday || marking)
            .accessibilityLabel(row.state.doneToday
                ? String(localized: "show.doneTodayLabel", defaultValue: "Done for today")
                : String(localized: "show.markToday", defaultValue: "Mark today done"))
        }
    }
}
