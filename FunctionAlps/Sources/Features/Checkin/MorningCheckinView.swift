import SwiftUI

/// The MORNING check-in screen (owner-validated 2026-11-12): last night, "Feeling for the day", "Reveal the rest of the day"
/// (the daily cards, saved to the daily check-in), the done button, and yesterday's missed check-in caught up below it.
/// `MorningCheckinViewModel` explains where each answer is kept.
struct MorningCheckinView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: MorningCheckinViewModel?

    var body: some View {
        ZStack {
            if let model {
                MorningCheckinScreen(model: model)
            }
        }
        .faWall()
        .navigationTitle(MomentSlot.morning.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let m = MorningCheckinViewModel(checkins: dependencies.checkins, members: dependencies.members, auth: dependencies.auth,
                                                gut: dependencies.gut, wearables: dependencies.wearables)
                model = m
                await m.prefill()
            }
        }
    }
}

private struct MorningCheckinScreen: View {
    @Bindable var model: MorningCheckinViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: FASpacing.md) {
                    header
                    if model.lock.isLocked { CheckinLockedNote(day: model.today) }
                    morningCards
                        .checkinLock(isLocked: model.lock.isLocked, day: model.today) { model.lock.unlock() }
                    revealRow
                    if model.revealOpen { revealedCards }
                    if let error = model.saveError { CheckinSaveErrorCard(error: error) }
                    doneButton
                    if model.offersYesterday { yesterdayPrompt }
                    Text(String(localized: "morning.note", defaultValue: "Nothing is required: the button works with whatever you answered."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
                        .id("showcase.morningBottom")
                    if model.yesterdayOpen, let yesterday = model.yesterdayModel { yesterdaySection(yesterday) }
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            #if DEBUG
            .task { await Showcase.scroll(proxy, to: "showcase.morningBottom", on: .morningBottom, anchor: .bottom) }
            .task { await Showcase.scroll(proxy, to: "showcase.yesterday", on: .morningYesterday) }
            #endif
        }
        .fullScreenCover(item: $model.ending) { rule in
            MorningEndView(rule: rule, onAction: { openAction($0) }, onContinue: { goHome() })
                .environment(dependencies)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: FASpacing.xs) {
            Text(String(localized: "checkin.morning.greeting", defaultValue: "Good morning"))
                .font(FATypography.largeTitle).foregroundStyle(FAColor.ink)
            let day = CheckinLockText.dayText(model.today)
            Text(String(localized: "morning.subtitle", defaultValue: "\(day) · two minutes, anything you skip is fine."))
                .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
        }
        .padding(.top, FASpacing.sm)
    }

    /// Last night and the feeling: read-only once saved.
    private var morningCards: some View {
        VStack(alignment: .leading, spacing: FASpacing.md) {
            Text(String(localized: "checkin.lastNight", defaultValue: "Last night"))
                .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4).padding(.top, 6)
            DimensionCardView(spec: FunctionalSchema.sleep, answers: sleepBinding, recordedNight: model.sleep.recordedNight, lookingForNight: model.sleep.syncingNight)
            DayFeelingCard(model: model)
        }
    }

    private var sleepBinding: Binding<DimAnswers> {
        Binding(get: { model.sleep.answers[.sleep] ?? .empty }, set: { model.sleep.answers[.sleep] = $0 })
    }

    private var revealRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { model.revealOpen.toggle() }
        } label: {
            FACard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "morning.reveal.title", defaultValue: "Reveal the rest of the day"))
                            .font(FATypography.headline).foregroundStyle(FAColor.forest)
                        Text(String(localized: "morning.reveal.subtitle", defaultValue: "Energy & focus, mood, stress, digestion, what fuelled you · optional"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: model.revealOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forest).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(model.revealOpen ? String(localized: "morning.reveal.open", defaultValue: "Expanded") : String(localized: "morning.reveal.closed", defaultValue: "Collapsed"))
    }

    /// The daily cards, saved to the daily check-in. Locked on their own once the daily check-in was saved.
    private var revealedCards: some View {
        VStack(alignment: .leading, spacing: FASpacing.md) {
            if model.reveal.lock.isLocked { CheckinLockedNote(day: model.today) }
            VStack(alignment: .leading, spacing: FASpacing.md) {
                CheckinSectionsView(model: model.reveal)
            }
            .checkinLock(isLocked: model.reveal.lock.isLocked, day: model.today) { model.reveal.lock.unlock() }
        }
        .transition(.opacity)
    }

    private var doneButton: some View {
        FAButton(title: model.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "morning.done", defaultValue: "Morning check-in done"),
                 isLoading: model.isSaving, isEnabled: model.canFinish) {
            Task {
                if await model.done() { savedMorning() }
            }
        }
    }

    // MARK: Yesterday

    private var yesterdayPrompt: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    FAMarkGlyph(color: FAColor.inkSecondary, size: 16).padding(.top, 2).accessibilityHidden(true)
                    Text(String(localized: "morning.yesterday.prompt", defaultValue: "You didn’t do yesterday’s check-in. Do it now to keep your momentum?"))
                        .font(FATypography.callout).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FAButton(title: String(localized: "morning.yesterday.yes", defaultValue: "Yes, do it now"), style: .secondary) {
                    Task { await model.openYesterday() }
                }
            }
        }
    }

    @ViewBuilder
    private func yesterdaySection(_ yesterday: CheckinMomentViewModel) -> some View {
        VStack(alignment: .leading, spacing: FASpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "morning.yesterday.label", defaultValue: "Yesterday"))
                        .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
                    Text(CheckinLockText.dayText(model.yesterday))
                        .font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                }
                Spacer()
                Text(String(localized: "morning.yesterday.badge", defaultValue: "catching up"))
                    .font(FATypography.label).foregroundStyle(FAColor.forest)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(FAColor.forest.opacity(0.09), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .id("showcase.yesterday")

            if yesterday.lock.isLocked { CheckinLockedNote(day: model.yesterday) }
            VStack(alignment: .leading, spacing: FASpacing.md) {
                CheckinSectionsView(model: yesterday)
            }
            .checkinLock(isLocked: yesterday.lock.isLocked, day: model.yesterday) { yesterday.lock.unlock() }

            if yesterday.nothingAnswered {
                FACard {
                    Text(String(localized: "checkin.nothingAnswered.hint", defaultValue: "Move at least one slider or pick an answer, then tap Save."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            if let error = yesterday.saveError { CheckinSaveErrorCard(error: error) }
            FAButton(title: yesterday.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "morning.yesterday.save", defaultValue: "Save yesterday"),
                     isLoading: yesterday.isSaving, isEnabled: !yesterday.lock.isLocked && (yesterday.gut.map(\.loaded) ?? true)) {
                Task { _ = await model.saveYesterday() }
            }
        }
        .padding(.top, FASpacing.md)
    }

    // MARK: After saving

    /// Saved: this morning's reminder is no longer needed; the first save is the moment to ask for notifications; today's focus is
    /// computed from the morning — it reads the night, and copes without the retired intent / priority pills.
    private func savedMorning() {
        let notifications = dependencies.notifications
        notifications.momentDone(.morning, day: dependencies.checkins.today)
        Task { await notifications.askIfNeeded() }
        let focus = dependencies.focus
        Task { await focus.load(recompute: true) }
    }

    private func goHome() {
        model.ending = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }

    /// "+ <action>": the practice's own card from the action bank when one matches, else the bank itself — then this screen
    /// steps aside so Back returns Home.
    private func openAction(_ action: MorningAction) {
        model.ending = nil
        let habits = dependencies.habits
        Task {
            await habits.loadBank()
            var cards: [ActionCardRow] = []
            if case .loaded(let loaded) = habits.bank { cards = loaded }
            let match = SignalActionMatch.card(for: action.habitHint, in: cards)
            let route: Route = match.map { Route.bankCard($0.id) } ?? Route.actionBank
            try? await Task.sleep(for: .milliseconds(350))
            router.replaceCheckin(with: route)
        }
    }
}
