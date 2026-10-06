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
                    TrackTodayCard(status: status, day: track.today, onOpen: onOpen)
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
                if let last {
                    TrackQuestionnaireRow(questionnaire: last, isToday: true, inProgress: dependencies.track.response(for: last.id) != nil) { onOpen(last.id) }
                }
            }
        }
    }
}

/// Days 1…14: the day's whole card.
private struct TrackTodayCard: View {
    @Environment(AppDependencies.self) private var dependencies
    let status: TrackStatus
    let day: TrackDay?
    let onOpen: (String) -> Void

    var body: some View {
        let track = dependencies.track
        let locale = track.locale
        let title = day.flatMap { TrackLogic.text($0.titleEn, $0.titleFr, locale: locale) } ?? ""
        let open = TrackLogic.openQuestionnaires(track.questionnaires, today: status.day, submitted: track.submitted)
        let calls = TrackLogic.openCalls(status.calls)
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                TrackCardHeader(eyebrow: String(localized: "track.dayOf", defaultValue: "Day \(status.day) of \(status.days)"), title: title)
                if let focus = day.flatMap({ TrackLogic.text($0.focusEn, $0.focusFr, locale: locale) }) {
                    Text(focus).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let day {
                    let videoURL = TrackLogic.text(day.videoUrlEn, day.videoUrlFr, locale: locale)
                        .flatMap { $0.lowercased().hasPrefix("https://") ? URL(string: $0) : nil }
                    TrackVideoView(url: videoURL) { Task { await track.videoPlayed(day: day.day) } }
                        .id(day.day)
                    if !day.actions.isEmpty { TrackActionsList(groups: TrackLogic.grouped(day.actions)) }
                    if let slug = day.readSlug { TrackReadRow(slug: slug, day: day.day) }
                }
                if !open.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(open) { q in
                            TrackQuestionnaireRow(questionnaire: q, isToday: q.day == status.day, inProgress: track.response(for: q.id) != nil) { onOpen(q.id) }
                        }
                    }
                }
                if !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calls, id: \.self) { TrackCallButton(call: $0) }
                    }
                }
                if status.day >= TrackLogic.progressFromDay { TrackProgressRow(status: status) }
            }
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
private struct TrackActionsList: View {
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

private struct TrackActionLine: View {
    @Environment(AppDependencies.self) private var dependencies
    let action: TrackAction

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
            Text(title)
                .font(FATypography.callout)
                .strikethrough(done)
                .foregroundStyle(done ? FAColor.inkSecondary : FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if action.isNew {
                Text(String(localized: "track.new", defaultValue: "New today"))
                    .font(FATypography.label).foregroundStyle(FAColor.forestDark)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(FAColor.forestSoft.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

/// The day's short read, in the library's reader.
private struct TrackReadRow: View {
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
private struct TrackCallButton: View {
    @Environment(\.openURL) private var openURL
    let call: TrackCall

    var body: some View {
        Button {
            if let url = TrackLogic.bookingURL(call) { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                Text(call.minutes >= 30
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
private struct TrackProgressRow: View {
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
