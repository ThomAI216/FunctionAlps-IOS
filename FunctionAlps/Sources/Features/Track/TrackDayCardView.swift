import SwiftUI

/// The day card in the mockups' order (`docs/foundation-cards/build.py`, `card_html`): the day and its dots, the
/// pillar, the title, the video, Today, the infographic, the questionnaire with "Why we ask", the calls and the
/// summary, the day's new actions under the card's own heading, the mini tip, the rest of the routine by moment,
/// how it will evolve, the library, the short read, and from day 7 where the member stands.
///
/// Every word of content is the practice's (`track_day.card_*`, the questionnaire's intro, the actions); the app
/// adds the section names only. New actions carry a "New" tag in words, never colour alone (rule 10).
struct TrackDayCardLayout: View {
    @Environment(AppDependencies.self) private var dependencies
    let status: TrackStatus
    let day: TrackDay
    let card: TrackDayCard
    let title: String
    let open: [TrackQuestionnaire]
    let calls: [TrackCall]
    let onOpen: (String) -> Void

    var body: some View {
        let track = dependencies.track
        let locale = track.locale
        let newActions = day.actions.filter(\.isNew)
        let routine = day.actions.filter { !$0.isNew }
        VStack(alignment: .leading, spacing: 16) {
            Group {
                TrackDayHeader(day: status.day, days: status.days, pillar: card.pillar, title: title)
                TrackDayVideo(day: day)
                if let today = card.today { TrackTodaySection(today: today) }
                if let image = TrackLogic.infographic(day, locale: locale) { TrackInfographic(url: image.url, alt: image.alt) }
                if !open.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(open) { q in
                            TrackQuestionnaireRow(questionnaire: q, isToday: q.day == status.day, inProgress: track.response(for: q.id) != nil) { onOpen(q.id) }
                            if q.day == status.day, let why = TrackLogic.text(q.introEn, q.introFr, locale: locale) {
                                TrackWhyWeAsk(text: why)
                            }
                        }
                    }
                }
                if !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calls, id: \.self) { TrackCallButton(call: $0) }
                    }
                }
                if track.summary != nil { TrackSummaryRow() }
            }
            Group {
                if !newActions.isEmpty || card.tryLabel != nil {
                    TrackTrySection(label: card.tryLabel, actions: newActions)
                }
                if let tip = card.tip { TrackTipBox(text: tip) }
                if !routine.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        TrackSectionTitle(text: String(localized: "track.card.routine", defaultValue: "Your routine"))
                        TrackActionsList(groups: TrackLogic.grouped(routine))
                    }
                }
                if !card.evolve.isEmpty { TrackEvolveList(steps: card.evolve) }
                if !card.openableLibrary.isEmpty { TrackLibraryList(items: card.openableLibrary) }
                if let slug = day.readSlug { TrackReadRow(slug: slug, day: day.day) }
                if status.day >= TrackLogic.progressFromDay { TrackProgressRow(status: status) }
            }
        }
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

/// "Foundation Track · Day N of 14", the fourteen dots, the pillar chip and the day's title.
private struct TrackDayHeader: View {
    let day: Int
    let days: Int
    let pillar: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((String(localized: "track.title", defaultValue: "Foundation Track") + " · "
                  + String(localized: "track.dayOf", defaultValue: "Day \(day) of \(days)")).uppercased())
                .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
            HStack(spacing: 4) {
                ForEach(1...max(days, 1), id: \.self) { i in
                    Circle()
                        .fill(i <= day ? FAColor.forestSoft : FAColor.forestSoft.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)   // the eyebrow says the day in words
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

/// Today: what it is · why it matters · how we use it (days 1–5), or one paragraph.
private struct TrackTodaySection: View {
    let today: TrackDayCard.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackSectionTitle(text: String(localized: "track.card.today", defaultValue: "Today"))
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
