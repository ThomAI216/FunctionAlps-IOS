import SwiftUI

/// "My health plan" — the page behind the Home card, laid out after the owner-approved mockup (2026-10-02):
/// the objective and goals, the journey through the phases, this week's priorities, the member's actions with
/// their week, the plan in detail, and what to read for it. Every word is the clinician's (rule 6); the page
/// counts and orders, nothing more (`PlanPageLogic`).
///
/// Two reads: the Habit Loop's day (`HabitsService`, shared with Home — loaded there, retried here) and the
/// plan's domain sections (`ProfileService.carePlan`). States (rule 5): loading, failed with retry, no plan yet
/// (the "appears after your call" note), loaded.
struct CarePlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var detail: CarePlan?

    var body: some View {
        let habits = dependencies.habits
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "home.healthPlan.title", defaultValue: "My health plan"), hairline: true)
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    switch habits.phase {
                    case .idle, .loading:
                        FALoadingState(message: String(localized: "careplan.loading", defaultValue: "Loading your plan…"))
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    case .failed(let message):
                        FACard {
                            FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"), message: message) {
                                Task { await habits.retry() }
                            }
                        }
                    case .loaded(let plan):
                        content(plan)
                    }
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            #if DEBUG
            .task { await Showcase.scroll(proxy, to: "showcase.objective", on: .careplan) }
            #endif
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let member = try? await dependencies.members.currentMember() {
                detail = await dependencies.profile.carePlan(patientId: member.patientId)
            }
        }
        .task { await dependencies.habits.loadNextCall() }
    }

    /// Every area is the clinician's; one not written yet is blurred (owner, 2026-10-02). Before the first plan the
    /// whole top waits behind the call; the member's actions — and the foundation bank — are there from day one.
    @ViewBuilder
    private func content(_ plan: HabitPlan) -> some View {
        let week = HabitEngine.planWeek(start: plan.header?.startDate, today: plan.day)
        if plan.header == nil {
            FACard {
                PlanLockedArea(reason: .awaitingCall(dependencies.habits.nextCall)) {
                    VStack(alignment: .leading, spacing: 18) {
                        PlanPlaceholderLines(lines: 3)
                        PlanPlaceholderLines(lines: 4)
                        PlanPlaceholderLines(lines: 1, chips: true)
                    }
                }
            }
        } else {
            intro(plan)
            objective(plan)
            if plan.phases.isEmpty { locked(String(localized: "careplan.journey", defaultValue: "Your journey"), lines: 4) } else { journey(plan, week: week) }
            if plan.priorities.isEmpty { locked(String(localized: "careplan.priorities", defaultValue: "This week's priorities"), lines: 1, chips: true) } else { priorities(plan.priorities) }
        }
        actions(plan)
        if let detail, !detail.sections.isEmpty { sections(detail) }
        let articles = PlanPageLogic.articles(plan)
        if !articles.isEmpty { reading(articles) }
        Text(String(localized: "careplan.updateNote", defaultValue: "Care plan is updated after each appointment by your practitioner."))
            .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
            .faFrost(cornerRadius: 14, horizontal: 14, vertical: 12)
    }

    // MARK: Sections

    /// "With [practitioner] · since September 2026" — who the plan is with and since when.
    @ViewBuilder
    private func intro(_ plan: HabitPlan) -> some View {
        let parts = [detail?.practitioner.trimmingCharacters(in: .whitespaces), detail?.startDate]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                .faFrost(cornerRadius: 12, horizontal: 12, vertical: 7)
        }
    }

    /// A plan area the clinician has not written yet: its heading, then the blurred stand-in.
    private func locked(_ title: String, lines: Int, chips: Bool = false) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                label(title)
                PlanLockedArea(reason: .notDefinedYet) { PlanPlaceholderLines(lines: lines, chips: chips) }
            }
        }
    }

    @ViewBuilder
    private func objective(_ plan: HabitPlan) -> some View {
        objectiveCard(plan).id("showcase.objective")
    }

    @ViewBuilder
    private func objectiveCard(_ plan: HabitPlan) -> some View {
        let line = plan.header?.objectiveLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goals = plan.goals.isEmpty ? (detail?.goals ?? []) : plan.goals
        if line.isEmpty && goals.isEmpty {
            locked(String(localized: "careplan.objective", defaultValue: "Your objective"), lines: 3)
        } else {
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    label(String(localized: "careplan.objective", defaultValue: "Your objective"))
                    if !line.isEmpty {
                        Text(line).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "target").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                .accessibilityHidden(true)
                            Text(goal).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func journey(_ plan: HabitPlan, week: Int?) -> some View {
        let total = PlanPageLogic.totalWeeks(plan.phases)
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                label(String(localized: "careplan.journey", defaultValue: "Your journey"))
                if let week {
                    Text(total.map { String(localized: "careplan.weekOf", defaultValue: "Week \(week) of \($0)") }
                         ?? String(localized: "home.healthPlan.week", defaultValue: "Week \(week)"))
                        .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                }
                ForEach(Array(plan.phases.enumerated()), id: \.offset) { index, phase in
                    phaseRow(phase, number: index + 1, state: PlanPageLogic.phaseState(phase, week: week))
                }
            }
        }
    }

    private func phaseRow(_ phase: HabitPlanPhase, number: Int, state: PlanPageLogic.PhaseState) -> some View {
        let weeks = phase.weekEnd.map { String(localized: "careplan.phase.weeks", defaultValue: "weeks \(phase.weekStart)–\($0)") }
            ?? String(localized: "careplan.phase.from", defaultValue: "from week \(phase.weekStart)")
        let status: String = switch state {
        case .done: String(localized: "careplan.phase.done", defaultValue: "done")
        case .current: String(localized: "careplan.phase.current", defaultValue: "in progress")
        case .upcoming: String(localized: "careplan.phase.upcoming", defaultValue: "coming up")
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: state == .done ? "checkmark.circle.fill" : state == .current ? "circle.inset.filled" : "circle.dashed")
                .font(.system(size: 18)).foregroundStyle(state == .upcoming ? FAColor.inkMuted : FAColor.forestSoft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "careplan.phase.meta", defaultValue: "Phase \(number) · \(weeks) · \(status)"))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                if let title = phase.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Text(title).font(FATypography.sans(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(state == .upcoming ? FAColor.inkSecondary : FAColor.ink)
                }
                if state == .current, let summary = phase.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    Text(summary).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state == .current ? FAColor.forestSoft.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func priorities(_ priorities: [String]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                label(String(localized: "careplan.priorities", defaultValue: "This week's priorities"))
                FlowLayout(spacing: 6) {
                    ForEach(Array(priorities.enumerated()), id: \.offset) { _, priority in
                        Text(priority)
                            .font(FATypography.sans(13, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.forestDark)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(FAColor.forestSoft.opacity(0.16), in: Capsule())
                    }
                }
            }
        }
    }

    private func actions(_ plan: HabitPlan) -> some View {
        let days = PlanPageLogic.week(plan)
        let totals = PlanPageLogic.weekTotals(days)
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                if plan.activeHabits.isEmpty {
                    label(String(localized: "careplan.actions", defaultValue: "My actions"))
                    PlanLockedArea(reason: .noActions) { PlanPlaceholderLines(lines: 4) }
                } else {
                    actionsList(plan, days: days, totals: totals)
                }
            }
        }
    }

    @ViewBuilder
    private func actionsList(_ plan: HabitPlan, days: [PlanPageLogic.WeekDay], totals: (done: Int, due: Int)) -> some View {
                HStack(alignment: .firstTextBaseline) {
                    label(String(localized: "careplan.actions", defaultValue: "My actions"))
                    Spacer()
                    if totals.due > 0 {
                        Text(String(localized: "careplan.actions.week", defaultValue: "This week · \(totals.done) of \(totals.due)"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                WeekStrip(days: days)
                ForEach(Array(PlanPageLogic.actionsByMoment(plan).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.slot?.label ?? String(localized: "plan.slot.anytime", defaultValue: "Anytime"))
                            .font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                        ForEach(group.habits, id: \.id) { habit in actionRow(habit, plan: plan) }
                    }
                }
                NavigationLink(value: Route.actionBank) {
                    Label(String(localized: "bank.addOne", defaultValue: "Add a foundation action"), systemImage: "plus.circle")
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
    }

    private func actionRow(_ habit: HabitRow, plan: HabitPlan) -> some View {
        let card = habit.habitBankId.flatMap { plan.cards[$0] }
        let kind = card?.cardKind.flatMap(ActionCardKind.init(rawValue:))
        let meta = [kind?.label, card?.durationMin.map { String(localized: "action.minutes", defaultValue: "\($0) min") }].compactMap { $0 }
        return NavigationLink(value: Route.action(habit.id)) {
            HStack(spacing: 10) {
                Image(systemName: kind?.symbol ?? "circle.dotted").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .frame(width: 32, height: 32)
                    .background(FAColor.forestSoft.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.title).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · ")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sections(_ plan: CarePlan) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                label(String(localized: "careplan.detail", defaultValue: "The plan in detail"))
                ForEach(plan.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: section.colorHex))
                                .frame(width: 28, height: 28)
                                .background(Color(hex: section.colorHex, opacity: 0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityHidden(true)
                            Text(section.category).font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        }
                        ForEach(section.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.status == .completed ? "checkmark.circle" : item.status == .paused ? "pause.circle" : "circle")
                                    .font(.system(size: 14)).foregroundStyle(item.status == .completed ? FAColor.forestSoft : FAColor.inkMuted)
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text).font(FATypography.sans(13, relativeTo: .subheadline))
                                        .foregroundStyle(item.status == .paused ? FAColor.inkSecondary : FAColor.ink).lineSpacing(4)
                                    Text(itemStatus(item.status)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func itemStatus(_ status: CarePlan.Item.Status) -> String {
        switch status {
        case .active: String(localized: "careplan.item.active", defaultValue: "In progress")
        case .completed: String(localized: "careplan.item.completed", defaultValue: "Done")
        case .paused: String(localized: "careplan.item.paused", defaultValue: "Paused")
        }
    }

    private func reading(_ articles: [(slug: String, title: String?)]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                label(String(localized: "careplan.reading", defaultValue: "To read for your plan"))
                ForEach(articles, id: \.slug) { article in
                    NavigationLink(value: Route.read(article.slug)) {
                        HStack(spacing: 10) {
                            Image(systemName: "book").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forest)
                                .frame(width: 32, height: 32)
                                .background(FAColor.forestSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .accessibilityHidden(true)
                            Text(article.title ?? String(localized: "action.read.fallback", defaultValue: "The article for this action"))
                                .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
    }
}

/// Monday to Sunday: full = everything due was done, half = some, ring = none, dash = nothing due, dotted = ahead.
/// Each state has its own shape, never only a colour (rule 10), and VoiceOver reads the numbers.
private struct WeekStrip: View {
    let days: [PlanPageLogic.WeekDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 5) {
                    Text(Self.symbols[safe: index] ?? "")
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    mark(day.state)
                        .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(a11y(day, index: index))
            }
        }
    }

    @ViewBuilder
    private func mark(_ state: PlanPageLogic.DayState) -> some View {
        switch state {
        case .full:
            Circle().fill(FAColor.forestSoft).overlay { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
        case .partial:
            Circle().strokeBorder(FAColor.forestSoft, lineWidth: 2)
                .overlay { Circle().trim(from: 0.25, to: 0.75).fill(FAColor.forestSoft).rotationEffect(.degrees(90)).padding(3) }
        case .none:
            Circle().strokeBorder(FAColor.inkMuted, lineWidth: 1.5)
        case .rest:
            Capsule().fill(FAColor.inkMuted.opacity(0.6)).frame(width: 10, height: 2)
        case .upcoming:
            Circle().strokeBorder(FAColor.inkMuted.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        }
    }

    private func a11y(_ day: PlanPageLogic.WeekDay, index: Int) -> String {
        let name = Self.names[safe: index] ?? day.day
        switch day.state {
        case .upcoming: return String(localized: "careplan.week.a11y.ahead", defaultValue: "\(name): ahead")
        case .rest: return String(localized: "careplan.week.a11y.rest", defaultValue: "\(name): nothing due")
        default: return String(localized: "careplan.week.a11y.count", defaultValue: "\(name): \(day.done) of \(day.due) done")
        }
    }

    /// Monday-first, in the language the app is drawn in.
    private static let symbols: [String] = mondayFirst(Calendar.current.veryShortStandaloneWeekdaySymbols)
    private static let names: [String] = mondayFirst(Calendar.current.standaloneWeekdaySymbols)
    private static func mondayFirst(_ sundayFirst: [String]) -> [String] { Array(sundayFirst.dropFirst()) + Array(sundayFirst.prefix(1)) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
