import SwiftUI

/// "About <signal>" (owner, 2026-11-11): the practice's own explanation of one check-in signal or of the Functional score —
/// what it is, what it feels like, what influences it (each row opens its "Why"), how it connects to the other signals, easy
/// ways to influence it, related reading, the sources. EVERY word of explanation is `signal_explanations` content (rule 6);
/// this view only lays it out. Reached from a Trends row, a signal's page, or the Functional score card.
/// States (rule 5): loading, failed with retry, empty (no approved content for this signal), loaded.
struct SignalAboutView: View {
    let key: String

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    /// The first influence starts open, as in the validated mockup.
    @State private var openRows: Set<Int> = [0]
    @State private var related: [LibraryArticle] = []

    private var about: SignalAboutKey? { SignalAboutKey(rawValue: key) }
    private var tint: Color { Color(hex: about?.tintHex ?? 0x2E5438) }

    var body: some View {
        let signals = dependencies.signals
        ZStack {
            if let content = signals.content(for: key), about != nil {
                page(content)
            } else {
                switch signals.phase {
                case .idle, .loading:
                    FALoadingState()
                case .failed(let message):
                    FAErrorState(title: String(localized: "signal.about.error", defaultValue: "Couldn't load this page"), message: message) {
                        Task { await signals.reload() }
                    }
                case .loaded:
                    unavailable
                }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await signals.loadIfNeeded() }
        .task { await loadSupporting() }
    }

    // MARK: States

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignalAboutHeader(title: about?.nodeName ?? key.capitalized, tint: tint)
            FACard {
                FAEmptyState(title: String(localized: "signal.about.empty.title", defaultValue: "Nothing to read here yet"),
                             message: String(localized: "signal.about.empty.message", defaultValue: "Your practice has not published this explanation yet."))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The page

    private func page(_ content: SignalExplanation.Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    SignalAboutHeader(title: content.title.isEmpty ? (about?.nodeName ?? key.capitalized) : content.title, tint: tint)
                    if !content.whatItIs.isEmpty { whatItIs(content) }
                    if !content.feelsHigh.isEmpty || !content.feelsLow.isEmpty { feels(content) }
                    if !content.influences.isEmpty { influences(content) }
                    if !content.connections.isEmpty { connects(content) }
                    if !content.plate.isEmpty { plate(content).id("about.plate") }
                    if !content.actions.isEmpty { actions(content) }
                    if !related.isEmpty { relatedReading }
                    if let line = content.safetyLine { safety(line) }
                    if !content.sources.isEmpty { SignalSourcesList(sources: content.sources).padding(.top, 4) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            #if DEBUG
            .task { await Showcase.scroll(proxy, to: "about.plate", on: .signalAboutEnergyBottom) }
            #endif
        }
    }

    private func caption(_ text: String) -> some View {
        TrendLabel(text: text).padding(.horizontal, 4).padding(.top, 6)
    }

    private func whatItIs(_ content: SignalExplanation.Content) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                TrendLabel(text: String(localized: "signal.about.whatItIs", defaultValue: "What it is"))
                Text(content.whatItIs)
                    .font(FATypography.sans(14.5, relativeTo: .body))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feels(_ content: SignalExplanation.Content) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                TrendLabel(text: String(localized: "signal.about.feels", defaultValue: "What it feels like"))
                if !content.feelsHigh.isEmpty {
                    SignalFeelsLine(word: content.feelsHighLabel ?? String(localized: "signal.about.high", defaultValue: "High"),
                                    text: content.feelsHigh, tintHex: SignalFeelsStyle.highTintHex, textHex: SignalFeelsStyle.highTextHex)
                }
                if !content.feelsLow.isEmpty {
                    SignalFeelsLine(word: content.feelsLowLabel ?? String(localized: "signal.about.low", defaultValue: "Low"),
                                    text: content.feelsLow, tintHex: SignalFeelsStyle.lowTintHex, textHex: SignalFeelsStyle.lowTextHex)
                }
            }
        }
    }

    @ViewBuilder
    private func influences(_ content: SignalExplanation.Content) -> some View {
        caption(String(localized: "signal.about.influences", defaultValue: "What influences it"))
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                if let intro = content.influencesIntro {
                    Text(intro)
                        .font(FATypography.sans(13.5, relativeTo: .callout))
                        .foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }
                ForEach(Array(content.influences.enumerated()), id: \.offset) { index, influence in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.7)) }
                    SignalInfluenceRow(influence: influence, tint: tint, isOpen: openRows.contains(index)) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if openRows.contains(index) { openRows.remove(index) } else { openRows.insert(index) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connects(_ content: SignalExplanation.Content) -> some View {
        caption(String(localized: "signal.about.connects", defaultValue: "How it connects"))
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Text(content.connectionsIntro
                     ?? String(localized: "signal.about.connects.caption", defaultValue: "Arrows show which way it flows. Line style shows how strong the evidence is."))
                    .font(FATypography.sans(12.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SignalConnectionMap(centre: key, connections: content.connections)
            }
        }
    }

    // MARK: What's on your plate (Energy)

    @ViewBuilder
    private func plate(_ content: SignalExplanation.Content) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                TrendLabel(text: String(localized: "signal.about.plate", defaultValue: "What's on your plate"))
                if let intro = content.plateIntro {
                    Text(intro)
                        .font(FATypography.sans(13.5, relativeTo: .callout))
                        .foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: content.plate.count, by: 2)), id: \.self) { start in
                        GridRow {
                            SignalPlateCard(item: content.plate[start], tint: tint)
                            if start + 1 < content.plate.count {
                                SignalPlateCard(item: content.plate[start + 1], tint: tint)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
                if let rule = content.plateRule {
                    VStack(alignment: .leading, spacing: 6) {
                        if !rule.title.isEmpty {
                            Text(rule.title).font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                        }
                        Text(rule.line)
                            .font(FATypography.sans(13, relativeTo: .footnote))
                            .foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !rule.evidence.isEmpty { SignalEvidenceBadge(evidence: SignalEvidence(raw: rule.evidence)) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FAColor.forest.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forest.opacity(0.18), lineWidth: 1) }
                }
            }
        }
    }

    // MARK: Easy ways to influence it

    private var bankCards: [ActionCardRow] {
        if case .loaded(let cards) = dependencies.habits.bank { return cards }
        return []
    }

    @ViewBuilder
    private func actions(_ content: SignalExplanation.Content) -> some View {
        caption(String(localized: "signal.about.actions", defaultValue: "Easy ways to influence it"))
        ForEach(Array(content.actions.enumerated()), id: \.offset) { _, action in
            let card = SignalActionMatch.card(for: action.habitHint, in: bankCards)
            let added = card.map { PlanAccess.habit(for: $0.id, in: dependencies.habits.plan) != nil } ?? false
            SignalActionRow(text: action.text, alreadyAdded: added) {
                // The matching card of the action bank (where the member adds it), else the bank itself — never an invented habit.
                router.push(card.map { Route.bankCard($0.id) } ?? Route.actionBank)
            }
        }
    }

    // MARK: Related reading

    @ViewBuilder
    private var relatedReading: some View {
        caption(String(localized: "signal.about.related", defaultValue: "Related reading"))
        ForEach(related) { article in
            NavigationLink(value: Route.read(article.slug)) {
                SignalRelatedCard(article: article, tint: tint)
            }
            .buttonStyle(.plain)
        }
    }

    private func safety(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(FAColor.inkSecondary).accessibilityHidden(true)
            Text(line)
                .font(FATypography.sans(12.5, relativeTo: .caption))
                .foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Supporting reads (fail soft: a block without data is simply not shown)

    private func loadSupporting() async {
        await dependencies.habits.loadBank()
        guard let about, !SignalRelated.topics(for: about).isEmpty,
              let member = try? await dependencies.members.currentMember(),
              let list = await dependencies.library.articles(patientId: member.patientId) else { return }
        related = SignalRelated.articles(for: about, in: list)
    }
}
