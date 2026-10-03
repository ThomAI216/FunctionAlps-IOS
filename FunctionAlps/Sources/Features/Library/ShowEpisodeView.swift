import SwiftUI

/// One episode of the show (approved mockup "iOS app — an episode", 2026-10-03): back to the Library, the replay with
/// its chapters, "Pillar · Episode N · 30 min", the serif title, then glass cards in order — Notes, Research, The
/// week (the one-week experiment), Article, FAQ. A document the API did not send is simply not there.
struct ShowEpisodeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var model: ShowEpisodeViewModel?

    var body: some View {
        ZStack {
            if let model {
                ShowEpisodeScreen(model: model) { dismiss() }
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: slug) {
            guard model == nil else { return }
            let m = ShowEpisodeViewModel(slug: slug, shows: dependencies.shows, members: dependencies.members,
                                         library: dependencies.library, notifications: dependencies.notifications)
            model = m
            await m.load()
        }
        .onDisappear { model?.stopPlayback() }
    }
}

private struct ShowEpisodeScreen: View {
    @Bindable var model: ShowEpisodeViewModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                backRow
                switch model.phase {
                case .loading:
                    FALoadingState().frame(height: 320)
                case .notFound:
                    FAErrorState(title: String(localized: "show.episodeUnavailable", defaultValue: "This episode isn't available"), message: "",
                                 retryTitle: String(localized: "show.backToLibrary", defaultValue: "Back to the Library")) { onBack() }
                        .frame(height: 360)
                case .unavailable:
                    FAErrorState(title: String(localized: "show.unavailable", defaultValue: "The show is unavailable right now. Try again in a minute."), message: "") {
                        Task { await model.retry() }
                    }
                    .frame(height: 360)
                case .loaded(let episode):
                    content(episode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
    }

    private var backRow: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                Text(String(localized: "library.title", defaultValue: "Library")).font(FATypography.sans(14, .semibold, relativeTo: .body))
            }
            .foregroundStyle(FAColor.forest)
            .faFrost(cornerRadius: 14, horizontal: 12, vertical: 7)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel(String(localized: "show.backToLibrary", defaultValue: "Back to the Library"))
    }

    @ViewBuilder
    private func content(_ episode: ShowEpisode) -> some View {
        let card = episode.card
        let topic = ShowLogic.trackTopic(card.track)
        ShowPlayerView(player: model.player, topic: topic, cover: model.covers[topic] ?? model.covers["foundations"])
        if let notes = episode.showNotes?.pick(model.lang), !notes.chapters.isEmpty {
            chapters(notes.chapters)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker(card).uppercased())
                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.3)
                .foregroundStyle(FALibraryColor.gold)
            Text(card.title.pick(model.lang))
                .font(FATypography.display(24, relativeTo: .title))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
        if !episode.member && episode.research == nil && episode.article == nil && episode.guide == nil && episode.faq == nil {
            Text(String(localized: "show.membersNoteApp", defaultValue: "The research, article, experiment and FAQ open for signed-in members."))
                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                .faFrost()
        }
        if let notes = episode.showNotes?.pick(model.lang), !notes.summary.showIsBlank || !notes.keyActions.isEmpty {
            ShowNotesCard(notes: notes)
        }
        if let research = episode.research?.pick(model.lang) {
            ShowResearchCard(research: research)
        }
        if let guide = model.guide, !guide.experiment.days.isEmpty {
            ShowExperimentCard(model: model, guide: guide)
                .id("show.experiment")
        }
        if let article = episode.article?.pick(model.lang) {
            ShowArticleCard(article: article)
        }
        if let faq = episode.faq?.pick(model.lang) {
            ShowFaqCard(faq: faq)
        }
    }

    private func kicker(_ card: ShowEpisodeCard) -> String {
        var parts = [ShowFormat.eyebrow(kind: card.kind, track: card.track, number: card.number, long: true)]
        if let m = ShowLogic.durationMinutes(card.durationSeconds) { parts.append(ShowFormat.minutes(m)) }
        return parts.joined(separator: " · ")
    }

    private func chapters(_ items: [ShowChapter]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, chapter in
                    Button {
                        if let s = ShowLogic.chapterSeconds(chapter.start) { model.player.seek(to: s) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(ShowLogic.chapterLabel(chapter.start))
                                .font(FATypography.sans(11.5, .bold, relativeTo: .caption)).monospacedDigit()
                                .foregroundStyle(FAColor.forest)
                            Text(chapter.title)
                                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.charcoal)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Color.white.opacity(0.75), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.player.hasMedia)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel(String(localized: "show.chapters", defaultValue: "Chapters"))
    }
}
