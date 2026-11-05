import SwiftUI

/// A Foundation Track questionnaire, full screen: the intro, one page per screen (2–3 questions, never
/// overwhelming), then the done page that sends the answers. Closing mid-way keeps what was answered — the
/// Home card offers it again.
///
/// States (rule 5): the questionnaire is read with the track (no extra load); unknown here (a stale card) → an
/// empty state with Close; a page save that fails is said quietly and retried on the next page; a failed send
/// shows the message and Try again.
struct TrackQuestionnaireView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let questionnaireId: String
    @State private var model: TrackQuestionnaireModel?

    var body: some View {
        Group {
            if let model {
                TrackQuestionnaireFlow(model: model) { dismiss() }
            } else if dependencies.track.questionnaire(questionnaireId) == nil {
                VStack(spacing: 16) {
                    FAEmptyState(title: String(localized: "track.questionnaire.missing.title", defaultValue: "This questionnaire isn't available"),
                                 message: String(localized: "track.questionnaire.missing.message", defaultValue: "Close this page and pull Home down to refresh."),
                                 systemImage: "list.bullet.clipboard")
                    ForestPillButton(title: String(localized: "action.close", defaultValue: "Close")) { dismiss() }
                        .padding(.horizontal, 22)
                }
                .frame(maxHeight: .infinity)
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .task {
            guard model == nil, let questionnaire = dependencies.track.questionnaire(questionnaireId) else { return }
            let m = TrackQuestionnaireModel(questionnaire: questionnaire, track: dependencies.track, members: dependencies.members,
                                            wearables: dependencies.wearables, notifications: dependencies.notifications)
            model = m
            await m.prepare()
        }
    }
}

private struct TrackQuestionnaireFlow: View {
    let model: TrackQuestionnaireModel
    let onClose: () -> Void
    @State private var busy = false
    @State private var editingBaseline = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.step {
                    case .intro: intro
                    case .page: page
                    case .done: done
                    }
                }
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .sheet(isPresented: $editingBaseline, onDismiss: { Task { await model.reloadProfile() } }) {
            NavigationStack { BaselineEditView() }
        }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await model.close()
                    onClose()
                }
            } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.ink)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
            progress
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    /// One segment per page that shows; the ones reached are forest (and VoiceOver reads "page 2 of 4").
    private var progress: some View {
        let total = max(model.pages.count, 1)
        let reached = model.pageIndex.map { $0 + 1 } ?? 0
        return HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < reached ? FAColor.forestSoft : ProfilePalette.surfaceSoft)
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "track.questionnaire.a11y.progress", defaultValue: "Page \(min(reached, total)) of \(total)"))
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            switch model.step {
            case .intro:
                ForestPillButton(title: String(localized: "track.questionnaire.start", defaultValue: "Start"), busy: busy) { run { await model.begin() } }
            case .page:
                ForestPillButton(title: model.isLastPage
                                 ? String(localized: "track.questionnaire.send", defaultValue: "Send my answers")
                                 : String(localized: "track.questionnaire.continue", defaultValue: "Continue"),
                                 enabled: model.canContinue, busy: busy) { run { await model.next() } }
                Button { model.back() } label: {
                    Text(String(localized: "action.back", defaultValue: "Go back")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .done:
                switch model.sending {
                case .failed:
                    ForestPillButton(title: String(localized: "action.retry", defaultValue: "Try again"), busy: busy) { run { await model.retrySend() } }
                    Button(action: onClose) {
                        Text(String(localized: "action.close", defaultValue: "Close")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                default:
                    ForestPillButton(title: String(localized: "action.close", defaultValue: "Close"), enabled: model.sending == .sent, action: onClose)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
        .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await work()
            busy = false
        }
    }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow.uppercased())
                .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.forestSoft)
            Text(model.title).font(FATypography.display(30, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let intro = model.intro {
                Text(intro).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var eyebrow: String {
        let day = String(localized: "track.questionnaire.day", defaultValue: "Day \(model.questionnaire.day)")
        guard let minutes = model.questionnaire.estMinutes else { return day }
        return day + " · " + String(localized: "track.questionnaire.minutes", defaultValue: "About \(minutes) min")
    }

    @ViewBuilder
    private var page: some View {
        if let page = model.page {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(page.questions) { question in
                    TrackQuestionView(question: question, model: model,
                                      onUpdateBaseline: { editingBaseline = true },
                                      onSkip: { run { await model.next() } })
                }
                if model.saveFailed {
                    Text(String(localized: "track.questionnaire.saveFailed", defaultValue: "Your answers couldn't be saved just now. We'll try again on the next page."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.sending {
            case .idle, .sending:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "track.questionnaire.sending", defaultValue: "Sending your answers…"))
                        .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, 40)
            case .failed(let message):
                FAErrorState(title: String(localized: "track.questionnaire.sendFailed", defaultValue: "Your answers weren't sent"), message: message, retryTitle: nil)
            case .sent:
                Image(systemName: "checkmark.seal").font(.system(size: 34, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    .accessibilityHidden(true)
                Text(String(localized: "track.questionnaire.thanks", defaultValue: "Thank you"))
                    .font(FATypography.display(30, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink)
                    .accessibilityAddTraits(.isHeader)
                if let text = model.doneText {
                    Text(text).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
