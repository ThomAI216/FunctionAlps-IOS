import SwiftUI

/// Which questionnaire the full-screen flow shows (Home owns the presentation, so a submit that hides this card
/// never tears the flow down mid-way).
struct TrackQuestionnaireRef: Identifiable, Hashable {
    let id: String
}

/// The Foundation Track's day, at the top of Home (Thomas, 2026-10-06): "Day N of 14" and the day's title, the
/// day's video, the day's actions by moment (ticked in place), the questionnaires still open, the calls the server
/// opened, and from day 7 where the member stands. Every number is the server's (`member_track_status`, rule 9);
/// every word of content is the practice's (the track's rows), in the app's language.
///
/// States (rule 5): not on the track → no card (most members); the first read in flight → no place held (like
/// today's actions: a skeleton that vanishes for everyone not on the track would shove Home around); `invited`
/// (launched by staff, the clock not started yet) → a quiet loading line; the content failed while on the track →
/// the error with a retry; after the last day → "your two weeks are done" until its questionnaire is in, then nothing.
struct FoundationTrackCard: View {
    @Environment(AppDependencies.self) private var dependencies
    let onOpen: (String) -> Void

    var body: some View {
        let track = dependencies.track
        if track.status?.state == .invited {
            FACard {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "track.loading", defaultValue: "Getting your day ready…"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        } else if let message = track.contentError {
            FACard {
                FAErrorState(title: String(localized: "track.error.title", defaultValue: "Couldn't load your day"), message: message) {
                    Task { await track.retry() }
                }
            }
        } else {
            switch track.mode {
            case .hidden:
                EmptyView()
            case .today:
                if let status = track.status {
                    TrackHomeCard(status: status, day: track.today)
                }
            case .finished(let questionnaireId):
                finished(questionnaireId.flatMap { track.questionnaire($0) })
            }
        }
    }

    private func finished(_ last: TrackQuestionnaire?) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                TrackCardHeader(eyebrow: String(localized: "track.title", defaultValue: "Foundation Track"),
                                title: String(localized: "track.finished.title", defaultValue: "Your two weeks are done"))
                if dependencies.track.summary != nil { TrackSummaryRow() }
                if let last {
                    TrackQuestionnaireRow(questionnaire: last, isToday: true, inProgress: dependencies.track.response(for: last.id) != nil) { onOpen(last.id) }
                }
            }
        }
    }
}

/// Days 1…14 on Home (Thomas, 2026-11-06): a short card that opens the day as its own page (`TrackDayPage`).
/// Day 1, before its questionnaire: "Welcome to your space", tap to start, and nothing else. After it (and on the
/// other days): the day's title and today's questionnaire done or waiting. The actions have their own card, by moment
/// (`TrackActionsCard`, Thomas 2026-11-07).
private struct TrackHomeCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    let status: TrackStatus
    let day: TrackDay?

    var body: some View {
        let track = dependencies.track
        let locale = track.locale
        let mode = TrackLogic.homeCard(day: status.day, questionnaires: track.questionnaires, submitted: track.submitted)
        let todays = track.questionnaires.first { $0.day == status.day }
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                Button { router.push(.trackDay) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text((String(localized: "track.title", defaultValue: "Foundation Track") + " · "
                              + String(localized: "track.dayOf", defaultValue: "Day \(status.day) of \(status.days)")).uppercased())
                            .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                        TrackDayDots(day: status.day, days: status.days)
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode == .welcome
                                     ? String(localized: "track.home.welcome", defaultValue: "Welcome to your space")
                                     : (day.flatMap { TrackLogic.text($0.titleEn, $0.titleFr, locale: locale) } ?? ""))
                                    .font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                Text(subtitle(mode, todays: todays, locale: locale))
                                    .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "track.home.a11y.open", defaultValue: "Opens today's page"))

                if case .day(let done) = mode {
                    if done == true, let todays {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(FAColor.accent).accessibilityHidden(true)
                            Text(String(localized: "track.home.questionnaireDoneNamed",
                                        defaultValue: "\(TrackLogic.text(todays.titleEn, todays.titleFr, locale: locale) ?? todays.titleEn): done"))
                                .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func subtitle(_ mode: TrackLogic.HomeCard, todays: TrackQuestionnaire?, locale: String) -> String {
        switch mode {
        case .welcome:
            return String(localized: "track.home.tapToStart", defaultValue: "Tap this card to start")
        case .day(let done):
            if done == false, let todays {
                let title = TrackLogic.text(todays.titleEn, todays.titleFr, locale: locale) ?? todays.titleEn
                return String(localized: "track.home.questionnaireWaiting", defaultValue: "Today's questionnaire: \(title)")
            }
            return String(localized: "track.home.openDay", defaultValue: "Open today's page")
        }
    }
}

/// Home's "Today's read" (Thomas, 2026-11-06): the day's short read, with its title once the library answers.
struct TrackHomeReadCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    let slug: String
    let day: Int
    @State private var title: String?

    var body: some View {
        Button {
            let track = dependencies.track
            Task { await track.readOpened(day: day) }
            router.push(.read(slug))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book").font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .frame(width: 44, height: 44)
                    .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "track.read.title", defaultValue: "Today's short read").uppercased())
                        .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                    Text(title ?? String(localized: "track.read.open", defaultValue: "Open in the library"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .task(id: slug) {
            // The title only; a failed read keeps "Open in the library" (the reader handles its own states).
            title = try? await dependencies.library.itemTitle(slug: slug)
        }
    }
}

/// Day 1's banner over the two squares (Thomas, 2026-11-06): the two things to try in the app first.
struct TrackFeatureBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                .accessibilityHidden(true)
            Text(String(localized: "track.home.banner", defaultValue: "Try the main features: log a meal and the functional check-in."))
                .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .modifier(FAGlassSurface(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// The day's video, played in the card; the first play is the day's `video` activity. A day without a video shows
/// nothing in its place (Thomas, 2026-11-06: no "coming soon" line; the videos arrive with their URLs).
struct TrackDayVideo: View {
    @Environment(AppDependencies.self) private var dependencies
    let day: TrackDay

    var body: some View {
        let track = dependencies.track
        let url = TrackLogic.text(day.videoUrlEn, day.videoUrlFr, locale: track.locale)
            .flatMap { $0.lowercased().hasPrefix("https://") ? URL(string: $0) : nil }
        if let url {
            TrackVideoView(url: url) { Task { await track.videoPlayed(day: day.day) } }
                .id(day.day)
        }
    }
}

/// The track's mark, an eyebrow and the title.
private struct TrackCardHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2").font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                .frame(width: 40, height: 40)
                .background(FAColor.forestSoft.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                Text(title).font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The day's actions by moment; each ticks in place, and opens its action card when it has one.
struct TrackActionsList: View {
    @Environment(AppDependencies.self) private var dependencies
    let groups: [TrackActionGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(label(group.moment).uppercased())
                        .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.actions) { TrackActionLine(action: $0) }
                }
            }
        }
    }

    private func label(_ moment: TrackMoment) -> String {
        switch moment {
        case .morning: HabitSlot.morning.label
        case .midday: HabitSlot.midday.label
        case .evening: HabitSlot.evening.label
        case .day: String(localized: "track.moment.day", defaultValue: "During the day")
        }
    }
}

struct TrackActionLine: View {
    @Environment(AppDependencies.self) private var dependencies
    let action: TrackAction
    /// Under the day card's "first thing to try" heading: a short "New" tag, and the action's how-to line.
    var underTryLabel = false

    var body: some View {
        let track = dependencies.track
        let card = action.habitBankId.flatMap { track.cards[$0] }
        let title = TrackLogic.actionTitle(action, card: card, locale: track.locale)
        let done = track.isDone(action)
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

            if let card {
                NavigationLink(value: Route.trackCard(card.id, face: action.face)) {
                    HStack(spacing: 8) {
                        line(title, done: done)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "action.a11y.open", defaultValue: "Opens how to do it"))
            } else {
                line(title, done: done)
            }
        }
    }

    private func line(_ title: String, done: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FATypography.callout)
                    .strikethrough(done)
                    .foregroundStyle(done ? FAColor.inkSecondary : FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if underTryLabel, let how = TrackLogic.text(action.howEn, action.howFr, locale: dependencies.track.locale) {
                    Text(how).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if action.isNew {
                Text(underTryLabel
                     ? String(localized: "track.card.new", defaultValue: "New")
                     : String(localized: "track.new", defaultValue: "New today"))
                    .font(FATypography.label).foregroundStyle(FAColor.forestDark)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(FAColor.forestSoft.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

/// The day's short read, in the library's reader.
struct TrackReadRow: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    let slug: String
    let day: Int

    var body: some View {
        Button {
            let track = dependencies.track
            Task { await track.readOpened(day: day) }
            router.push(.read(slug))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .frame(width: 40, height: 40)
                    .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                Text(String(localized: "track.read.title", defaultValue: "Today's short read"))
                    .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One questionnaire to open: today's, or an earlier one not sent yet.
struct TrackQuestionnaireRow: View {
    @Environment(AppDependencies.self) private var dependencies
    let questionnaire: TrackQuestionnaire
    let isToday: Bool
    let inProgress: Bool
    let action: () -> Void

    var body: some View {
        let title = TrackLogic.text(questionnaire.titleEn, questionnaire.titleFr, locale: dependencies.track.locale) ?? questionnaire.titleEn
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .frame(width: 40, height: 40)
                    .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday
                         ? String(localized: "track.questionnaire.today", defaultValue: "Today's questionnaire")
                         : String(localized: "track.questionnaire.open", defaultValue: "Still open · Day \(questionnaire.day)"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    Text(title).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                    if let line = subtitle {
                        Text(line).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        if inProgress { return String(localized: "track.questionnaire.inProgress", defaultValue: "Started · pick up where you left off") }
        return questionnaire.estMinutes.map { String(localized: "track.questionnaire.minutes", defaultValue: "About \($0) min") }
    }
}

/// A call the server opened: the practice's booking page, in Safari.
struct TrackCallButton: View {
    @Environment(\.openURL) private var openURL
    let call: TrackCall

    var body: some View {
        Button {
            if let url = TrackLogic.bookingURL(call) { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                Text(call.gated
                     ? String(localized: "track.call.review", defaultValue: "Book your review call with Thomas · \(call.minutes) min")
                     : String(localized: "track.call.book", defaultValue: "Book a call with Thomas · \(call.minutes) min"))
                    .font(FATypography.sans(14, .semibold, relativeTo: .body))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(FAColor.forestDark)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "track.call.hint", defaultValue: "Opens the booking page in Safari"))
    }
}

/// From day 7: questionnaires sent, meals logged against expected, and the energy and protein ranges — all the
/// server's figures, formatted here.
struct TrackProgressRow: View {
    let status: TrackStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "track.progress.title", defaultValue: "Where you stand").uppercased())
                .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                chip("checklist", String(localized: "track.progress.questionnaires", defaultValue: "Questionnaires \(status.modulesDone)/\(status.modulesTotal)"))
                if let pct = status.mealsPct {
                    chip("camera", String(localized: "track.progress.meals", defaultValue: "Meals logged: \(pct.formatted(.percent))"))
                }
                if let kcal = TrackLogic.range(status.energyKcalLow, status.energyKcalHigh) {
                    chip("flame", String(localized: "track.range.kcal", defaultValue: "~\(kcal.0)–\(kcal.1) kcal"))
                }
                if let protein = TrackLogic.range(status.proteinGLow, status.proteinGHigh) {
                    chip("fork.knife", String(localized: "track.range.protein", defaultValue: "~\(protein.0)–\(protein.1) g protein"))
                }
            }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text(text).font(FATypography.sans(12, .medium, relativeTo: .caption))
        }
        .foregroundStyle(FAColor.ink)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .modifier(FAGlassSurface(cornerRadius: 12, inset: true))
    }
}
