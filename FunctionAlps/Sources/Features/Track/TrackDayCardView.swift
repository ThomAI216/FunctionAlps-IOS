import SwiftUI

/// The day, as its own page (Thomas, 2026-11-06): Home holds a short card ("Welcome to your space" on day 1) and a
/// tap opens this. The old long card is cut into separate cards, in the mockups' order: where you start (the day,
/// its dots, the pillar, the title, the video when there is one, the day's text, the infographic) · today's
/// questionnaire with "Why we ask" inside · the calls and the summary · the day's new actions, each a mini card ·
/// the mini tip · the rest of the routine · how it will evolve · the library, the short read and, from day 7,
/// where the member stands.
///
/// Every word of content is the practice's (`track_day.card_*`, the questionnaire's intro, the actions); the app
/// adds the section names only. States (rule 5): the track is read with Home; off the track or still reading → a
/// calm loading line; the content failed → the error with a retry.
struct TrackDayPage: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var questionnaire: TrackQuestionnaireRef?

    var body: some View {
        let track = dependencies.track
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "track.title", defaultValue: "Foundation Track"), hairline: true)
            if let message = track.contentError {
                FAErrorState(title: String(localized: "track.error.title", defaultValue: "Couldn't load your day"), message: message) {
                    Task { await track.retry() }
                }
                .frame(maxHeight: .infinity)
            } else if let status = track.status, status.state == .active, let day = track.today {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        TrackDayCards(status: status, day: day) { questionnaire = TrackQuestionnaireRef(id: $0) }
                            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, FASpacing.navBarClearance)
                            #if DEBUG
                            .background(alignment: .top) { ShowcasePageMarks() }
                            #endif
                    }
                    #if DEBUG
                    .task {
                        guard ShowcaseTrack.isOn, ShowcaseTrack.page > 0 else { return }
                        try? await Task.sleep(for: .seconds(4))
                        proxy.scrollTo("fa-page-\(ShowcaseTrack.page)", anchor: .top)
                    }
                    #endif
                }
            } else {
                FALoadingState().frame(maxHeight: .infinity)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $questionnaire) { TrackQuestionnaireView(questionnaireId: $0.id) }
    }
}

/// The day's cards, one under the other.
private struct TrackDayCards: View {
    @Environment(AppDependencies.self) private var dependencies
    let status: TrackStatus
    let day: TrackDay
    let onOpen: (String) -> Void

    var body: some View {
        let track = dependencies.track
        let locale = track.locale
        let card = TrackLogic.card(day, locale: locale)
        let title = TrackLogic.text(day.titleEn, day.titleFr, locale: locale) ?? ""
        let open = TrackLogic.openQuestionnaires(track.questionnaires, today: status.day, submitted: track.submitted)
        let todays = track.questionnaires.first { $0.day == status.day }
        let calls = TrackLogic.openCalls(status.calls)
        let newActions = day.actions.filter(\.isNew)
        let routine = day.actions.filter { !$0.isNew }
        VStack(spacing: 12) {
            // Where you start: the day, the dots, the title, the day's text.
            FACard {
                VStack(alignment: .leading, spacing: 14) {
                    TrackDayHeader(day: status.day, days: status.days, pillar: card?.pillar, title: title)
                    TrackDayVideo(day: day)
                    if let today = card?.today {
                        TrackTodaySection(today: today)
                    } else if let focus = TrackLogic.text(day.focusEn, day.focusFr, locale: locale) {
                        Text(focus).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let image = TrackLogic.infographic(day, locale: locale) { TrackInfographic(url: image.url, alt: image.alt) }
                }
            }
            // Today's questionnaire, with "Why we ask" inside; earlier ones not sent yet; or today's, done.
            if !open.isEmpty || todays.map({ track.submitted.contains($0.id) }) == true {
                FACard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(open) { q in
                            TrackQuestionnaireRow(questionnaire: q, isToday: q.day == status.day, inProgress: track.response(for: q.id) != nil) { onOpen(q.id) }
                            if q.day == status.day, let why = TrackLogic.text(q.introEn, q.introFr, locale: locale) {
                                TrackWhyWeAsk(text: why)
                            }
                        }
                        if let todays, track.submitted.contains(todays.id) { TrackQuestionnaireDone(questionnaire: todays) }
                    }
                }
            }
            if !calls.isEmpty || track.summary != nil {
                FACard {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calls, id: \.self) { TrackCallButton(call: $0) }
                        if track.summary != nil { TrackSummaryRow() }
                    }
                }
            }
            // The day's new actions, each a mini card of its own.
            ForEach(newActions) { action in
                FACard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((card?.tryLabel ?? (status.day == 1
                              ? String(localized: "track.home.firstAction", defaultValue: "Try your first action")
                              : String(localized: "track.new", defaultValue: "New today"))).uppercased())
                            .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                            .accessibilityAddTraits(.isHeader)
                        TrackActionLine(action: action, underTryLabel: true)
                    }
                }
            }
            if let tip = card?.tip { TrackTipBox(text: tip) }
            if !routine.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 6) {
                        TrackSectionTitle(text: String(localized: "track.card.routine", defaultValue: "Your routine"))
                        TrackActionsList(groups: TrackLogic.grouped(routine))
                    }
                }
            }
            if let steps = card?.evolve, !steps.isEmpty {
                FACard { TrackEvolveList(steps: steps) }
            }
            let library = card?.openableLibrary ?? []
            if !library.isEmpty || day.readSlug != nil || status.day >= TrackLogic.progressFromDay {
                FACard {
                    VStack(alignment: .leading, spacing: 12) {
                        if !library.isEmpty { TrackLibraryList(items: library) }
                        if let slug = day.readSlug { TrackReadRow(slug: slug, day: day.day) }
                        if status.day >= TrackLogic.progressFromDay { TrackProgressRow(status: status) }
                    }
                }
            }
        }
    }
}

/// Today's questionnaire, sent: said in words and with the mark (rule 10).
private struct TrackQuestionnaireDone: View {
    @Environment(AppDependencies.self) private var dependencies
    let questionnaire: TrackQuestionnaire

    var body: some View {
        let title = TrackLogic.text(questionnaire.titleEn, questionnaire.titleFr, locale: dependencies.track.locale) ?? questionnaire.titleEn
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(FAColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                Text(String(localized: "track.home.questionnaireDone", defaultValue: "Questionnaire done"))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section name on the day card (a header for VoiceOver).
struct TrackSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Foundation Track · Day N of 14", the fourteen dots across the whole card (Thomas, 2026-11-06), the pillar chip
/// and the day's title.
struct TrackDayHeader: View {
    let day: Int
    let days: Int
    let pillar: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((String(localized: "track.title", defaultValue: "Foundation Track") + " · "
                  + String(localized: "track.dayOf", defaultValue: "Day \(day) of \(days)")).uppercased())
                .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
            TrackDayDots(day: day, days: days)
            if let pillar {
                Text(pillar)
                    .font(FATypography.label).foregroundStyle(FAColor.forestDark)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(FAColor.forestSoft.opacity(0.18), in: Capsule())
            }
            Text(title).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The fourteen days as dots spread across the card's width, the days reached filled (the eyebrow says the day in
/// words, so VoiceOver skips them).
struct TrackDayDots: View {
    let day: Int
    let days: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(days, 1), id: \.self) { i in
                Circle()
                    .fill(i <= day ? FAColor.forestSoft : FAColor.forestSoft.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 18)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The day's text: its labelled parts (why it matters · how we use it), or one paragraph. No "Today" heading
/// (Thomas, 2026-11-06): the card itself is the day.
private struct TrackTodaySection: View {
    let today: TrackDayCard.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch today {
            case .paragraph(let text):
                Text(text).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            case .parts(let parts):
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.label).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestDark)
                        Text(part.text).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Thomas's infographic, 4:5, read to VoiceOver by what it shows. A failed load leaves a calm empty pane.
private struct TrackInfographic: View {
    let url: URL
    let alt: String?

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(FAColor.forestSoft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(FAColor.forestMist.opacity(0.5))
                    default:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(alt ?? "")
            .accessibilityAddTraits(.isImage)
            .accessibilityHidden(alt == nil)
    }
}

/// "Why we ask": the day's questionnaire intro, under its button.
private struct TrackWhyWeAsk: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "track.card.why", defaultValue: "Why we ask"))
                .font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

/// The day's new actions under the card's own heading ("First thing to try · …", else "New today").
private struct TrackTrySection: View {
    let label: String?
    let actions: [TrackAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TrackSectionTitle(text: label ?? String(localized: "track.new", defaultValue: "New today"))
            if actions.isEmpty {
                Text(String(localized: "track.card.nothingNew", defaultValue: "Nothing new today. Keep what you've started."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                    .padding(.top, 4)
            } else {
                ForEach(actions) { TrackActionLine(action: $0, underTryLabel: true) }
            }
        }
    }
}

private struct TrackTipBox: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "track.card.tip", defaultValue: "Mini tip").uppercased())
                .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestDark)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
    }
}

/// How it will evolve: when, then what changes.
private struct TrackEvolveList: View {
    let steps: [TrackDayCard.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackSectionTitle(text: String(localized: "track.card.evolve", defaultValue: "How it will evolve"))
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.when).font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestDark)
                    Text(step.text).font(FATypography.callout).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The library items the card points to — only those with a slug, opened in the library's reader.
private struct TrackLibraryList: View {
    @Environment(AppRouter.self) private var router
    let items: [TrackDayCard.LibraryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackSectionTitle(text: String(localized: "track.card.library", defaultValue: "From the library"))
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if let slug = item.slug {
                    Button { router.push(.read(slug)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forest)
                                .frame(width: 40, height: 40)
                                .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                if !item.kind.isEmpty {
                                    Text(item.kind).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                }
                                Text(item.title).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                    .multilineTextAlignment(.leading)
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
            }
        }
    }
}
