import SwiftUI

/// One action, opened from "Today's actions", the plan page or the action bank: what to do, how, a demonstration,
/// why, and what to read — the practice's action card (CLINICAL → Action cards), around the clinician's habit when
/// there is one. Laid out exactly as CLINICAL's preview draws it. Every word is the practice's (rule 6); the app
/// adds the controls only.
///
/// From a habit: "Done" is today's check-off (the same completion the Home row writes); "Not today" records
/// nothing — the action comes back at its next moment, which is what the line says; a member's OWN action can be
/// removed. From the bank: "Add to my plan" at the moment the member picks (the card's suggestion first).
/// A habit without a card still opens, on its own words.
struct ActionCardView: View {
    enum Source: Hashable {
        case habit(String)
        case bankCard(String)
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let source: Source

    @State private var face: HabitFace?
    @State private var skipped = false
    @State private var busy = false
    @State private var writeFailed = false

    var body: some View {
        let habits = dependencies.habits
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                backRow
                switch habits.phase {
                case .idle, .loading:
                    FALoadingState()
                case .failed(let message):
                    FACard {
                        FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"), message: message) {
                            Task { await habits.retry() }
                        }
                    }
                case .loaded(let plan):
                    switch source {
                    case .habit(let habitId):
                        if let habit = plan.habits.first(where: { $0.id == habitId }) {
                            habitPage(plan: plan, habit: habit)
                        } else {
                            missing
                        }
                    case .bankCard(let cardId):
                        if let card = bankCard(cardId, plan: plan) {
                            bankPage(plan: plan, card: card)
                        } else if case .loading = habits.bank {
                            FALoadingState()
                        } else {
                            missing
                        }
                    }
                }
                #if DEBUG
                Color.clear.frame(height: 0).id("showcase.end")
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        #if DEBUG
        .task { await Showcase.scroll(proxy, to: "showcase.steps", on: .cardMiddle) }
        .task { await Showcase.scroll(proxy, to: "showcase.end", on: .cardBottom, anchor: UnitPoint(x: 0.5, y: 0.88)) }
        #endif
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if case .bankCard = source { await dependencies.habits.loadBank() }
        }
        .alert(String(localized: "error.title", defaultValue: "Something went wrong"), isPresented: $writeFailed) {
            Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "bank.writeFailed", defaultValue: "Your plan could not be updated. Please try again."))
        }
    }

    private var missing: some View {
        FACard {
            FAEmptyState(title: String(localized: "action.missing.title", defaultValue: "This action is no longer in your plan"),
                         message: String(localized: "action.missing.message", defaultValue: "Your practitioner may have changed it."))
        }
    }

    private func bankCard(_ id: String, plan: HabitPlan) -> ActionCardRow? {
        if case .loaded(let cards) = dependencies.habits.bank, let card = cards.first(where: { $0.id == id }) { return card }
        return plan.cards[id]
    }

    private var backRow: some View {
        Button { dismiss() } label: {
            Text("‹ " + (source.isBank
                         ? String(localized: "bank.title", defaultValue: "Foundation actions")
                         : String(localized: "plan.today.title", defaultValue: "Today's actions")))
                .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                .faFrost(cornerRadius: 14, horizontal: 12, vertical: 8)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func habitPage(plan: HabitPlan, habit: HabitRow) -> some View {
        let content = ActionCardLogic.content(card: habit.habitBankId.flatMap { plan.cards[$0] }, habit: habit, locale: TodayFocus.locale())
        let todayFace = HabitEngine.face(habit, band: dependencies.focus.focus?.readiness?.bandValue).face
        let shown = face ?? todayFace
        let dueToday = habit.isActive && HabitEngine.isDue(habit.frequencyRule, on: plan.day, start: habit.createdDay)
        let completionId = HabitEngine.completionId(plan.completions, habit: habit.id, on: plan.day)

        cardBody(content, slot: habit.slotValue, face: shown)
        if dueToday { actions(habit: habit, completionId: completionId, plan: plan) }
        if habit.isSelfInitiated { removeButton(habit) }
    }

    @ViewBuilder
    private func bankPage(plan: HabitPlan, card: ActionCardRow) -> some View {
        let content = ActionCardLogic.content(card: card, habit: nil, locale: TodayFocus.locale())
        cardBody(content, slot: card.defaultSlot.flatMap(HabitSlot.init(rawValue:)), face: face ?? .standard)
        if let own = PlanAccess.habit(for: card.id, in: plan) {
            Text(String(localized: "bank.inPlan", defaultValue: "In your plan ✓"))
                .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                .faFrost(cornerRadius: 14, horizontal: 14, vertical: 10)
                .frame(maxWidth: .infinity)
            if own.isSelfInitiated { removeButton(own) }
        } else {
            addMenu(card)
        }
    }

    @ViewBuilder
    private func cardBody(_ content: ActionCardContent, slot: HabitSlot?, face shown: HabitFace) -> some View {
        header(content, slot: slot, face: shown)
        if content.kind == .breath { BreathPacer(minutes: content.durationMin) }
        if content.easyTitle != nil || content.furtherTitle != nil { versions(content, selected: shown) }
        if content.video != nil || content.youtubeQuery != nil { media(content) }
        if !content.steps.isEmpty { steps(content.steps).id("showcase.steps") }
        if let why = content.why { whyCard(why) }
        if let article = content.article { articleCard(article) }
    }

    /// "Add to my plan" at a moment of the member's choosing — the card's own suggestion listed first.
    private func addMenu(_ card: ActionCardRow) -> some View {
        let suggested = card.defaultSlot.flatMap(HabitSlot.init(rawValue:))
        let choices: [HabitSlot?] = [suggested] + (HabitSlot.order.map { Optional($0) } + [nil]).filter { $0 != suggested }
        return Menu {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, slot in
                Button(slot?.label ?? String(localized: "plan.slot.anytime", defaultValue: "Anytime")) { add(card, slot: slot) }
            }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(String(localized: "bank.add", defaultValue: "Add to my plan")).font(FATypography.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(FAColor.brand, in: RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
        }
        .disabled(busy)
        .accessibilityHint(String(localized: "bank.add.hint", defaultValue: "Choose the moment of the day"))
        .padding(.top, 4)
    }

    private func add(_ card: ActionCardRow, slot: HabitSlot?) {
        busy = true
        Task {
            let ok = await dependencies.habits.add(card: card, slot: slot)
            busy = false
            if !ok { writeFailed = true }
        }
    }

    private func removeButton(_ habit: HabitRow) -> some View {
        Button {
            busy = true
            Task {
                let ok = await dependencies.habits.remove(ownHabitId: habit.id)
                busy = false
                if ok { if case .habit = source { dismiss() } } else { writeFailed = true }
            }
        } label: {
            Text(String(localized: "bank.remove", defaultValue: "Remove from my plan"))
                .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                .faFrost(cornerRadius: 14, horizontal: 14, vertical: 9)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: Pieces

    private func header(_ content: ActionCardContent, slot: HabitSlot?, face: HabitFace) -> some View {
        let title = face == .easy ? (content.easyTitle ?? content.title) : face == .progression ? (content.furtherTitle ?? content.title) : content.title
        let detail = face == .easy ? (content.easyDescription ?? content.description)
            : face == .progression ? (content.furtherDescription ?? content.description) : content.description
        return FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let url = content.imageURL {
                    CachedCoverImage(url: url)
                        .frame(height: 170).frame(maxWidth: .infinity)
                        .background(FAColor.forestMist)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let meta = metaLine(content, slot: slot) {
                        Text(meta.uppercased())
                            .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                    }
                    Text(title).font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
    }

    private func metaLine(_ content: ActionCardContent, slot: HabitSlot?) -> String? {
        let moment = slot?.label ?? String(localized: "plan.slot.anytime", defaultValue: "Anytime")
        let parts = [content.kind?.label, moment, content.durationMin.map { String(localized: "action.minutes", defaultValue: "\($0) min") }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private struct VersionOption: Identifiable {
        let face: HabitFace
        let label: String
        var id: String { label }
    }

    private func versions(_ content: ActionCardContent, selected: HabitFace) -> some View {
        var options: [VersionOption] = []
        if content.easyTitle != nil { options.append(VersionOption(face: .easy, label: String(localized: "action.version.easy", defaultValue: "Gentle"))) }
        options.append(VersionOption(face: .standard, label: String(localized: "action.version.standard", defaultValue: "Standard")))
        if content.furtherTitle != nil { options.append(VersionOption(face: .progression, label: String(localized: "action.version.further", defaultValue: "Further"))) }
        return FACard {
            VStack(alignment: .leading, spacing: 8) {
                label(String(localized: "action.version.title", defaultValue: "Today's version"))
                HStack(spacing: 6) {
                    ForEach(options) { option in
                        let on = option.face == selected
                        Button { withAnimation(.easeOut(duration: 0.2)) { face = option.face } } label: {
                            Text(option.label).font(FATypography.sans(13, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(on ? Color.white : FAColor.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(on ? FAColor.forest : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func media(_ content: ActionCardContent) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                if let video = content.video {
                    Button { openURL(video.url) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FAColor.charcoal).frame(height: 150)
                            Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text(video.title ?? String(localized: "action.video.watch", defaultValue: "Watch the demonstration"))
                                .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(.white.opacity(0.92))
                                .padding(12)
                        }
                        .frame(height: 150)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(video.title ?? String(localized: "action.video.watch", defaultValue: "Watch the demonstration"))
                }
                if let query = content.youtubeQuery, let url = ActionCardLogic.youtubeSearchURL(query) {
                    Button { openURL(url) } label: {
                        Text(String(localized: "action.youtube", defaultValue: "Search “\(query)” on YouTube ↗"))
                            .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func steps(_ steps: [String]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "action.how", defaultValue: "How to do it")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                            .frame(width: 22, height: 22)
                            .background(FAColor.forestSoft.opacity(0.16), in: Circle())
                            .accessibilityHidden(true)
                        Text(step).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "action.a11y.step", defaultValue: "Step \(index + 1): \(step)"))
                }
            }
        }
    }

    private func whyCard(_ why: String) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "action.why", defaultValue: "Why it is in your plan")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                Text(why).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func articleCard(_ article: (slug: String, title: String?)) -> some View {
        Button { router.push(.read(article.slug)) } label: {
            FACard {
                HStack(spacing: 12) {
                    Image(systemName: "book").font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.forest)
                        .frame(width: 44, height: 44)
                        .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "action.read", defaultValue: "Read in the library")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        Text(article.title ?? String(localized: "action.read.fallback", defaultValue: "The article for this action"))
                            .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actions(habit: HabitRow, completionId: String?, plan: HabitPlan) -> some View {
        let done = completionId != nil
        let action = HabitAction(id: habit.id, title: habit.title, detail: nil, slot: habit.slotValue, completionId: completionId,
                                 streak: HabitEngine.currentStreak(habit, completions: plan.completions, today: plan.day))
        VStack(spacing: 8) {
            if skipped && !done {
                Text(String(localized: "action.notToday.note", defaultValue: "Noted. It comes back at its next moment — no problem."))
                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .faFrost(cornerRadius: 14, horizontal: 14, vertical: 10)
                    .frame(maxWidth: .infinity)
            }
            FAButton(title: done
                     ? String(localized: "action.done.undo", defaultValue: "Done ✓ · Undo")
                     : String(localized: "action.card.done", defaultValue: "Done")) {
                let habits = dependencies.habits
                Task { await habits.toggle(action) }
            }
            if !done && !skipped {
                FAButton(title: String(localized: "action.notToday", defaultValue: "Not today"), style: .tertiary) { skipped = true }
                    .modifier(FAGlassSurface(cornerRadius: FACornerRadius.md))
            }
        }
        .padding(.top, 4)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
    }
}

/// A calm, wordless pacer for a breathing card: the circle swells and settles while a timer runs for the card's
/// duration. It sets no rhythm of its own in words — the steps above say how to breathe (rule 6).
private struct BreathPacer: View {
    let minutes: Int?
    @State private var running = false
    @State private var remaining = 0
    @State private var expanded = false

    var body: some View {
        FACard {
            VStack(spacing: 12) {
                Circle()
                    .fill(RadialGradient(colors: [FAColor.forestSoft.opacity(0.38), FAColor.forestSoft.opacity(0.12)], center: .center, startRadius: 4, endRadius: 80))
                    .overlay { Circle().strokeBorder(FAColor.forestSoft, lineWidth: 2) }
                    .frame(width: 132, height: 132)
                    .scaleEffect(running ? (expanded ? 1.0 : 0.78) : 0.86)
                    .animation(running ? .easeInOut(duration: 5).repeatForever(autoreverses: true) : .easeOut(duration: 0.4), value: expanded)
                    .accessibilityHidden(true)
                Text(running ? clock(remaining) : String(localized: "action.breath.follow", defaultValue: "Follow the steps with the circle"))
                    .font(running ? FATypography.display(22, relativeTo: .title2) : FATypography.sans(13, relativeTo: .subheadline))
                    .foregroundStyle(running ? FAColor.ink : FAColor.inkSecondary)
                    .monospacedDigit()
                FAButton(title: running
                         ? String(localized: "action.breath.stop", defaultValue: "Stop")
                         : String(localized: "action.breath.start", defaultValue: "Start") + (minutes.map { " · " + String(localized: "action.minutes", defaultValue: "\($0) min") } ?? "")) {
                    running.toggle()
                    expanded = running
                    remaining = (minutes ?? 3) * 60
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: running) {
            guard running else { return }
            while running, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
            if remaining <= 0 { running = false; expanded = false }
        }
    }

    private func clock(_ seconds: Int) -> String { String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
}

private extension ActionCardView.Source {
    var isBank: Bool { if case .bankCard = self { return true } else { return false } }
}
