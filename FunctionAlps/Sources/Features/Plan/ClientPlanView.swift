import SwiftUI

/// "My health plan", the entry: the client's plan as the practice shared it (programmes, objectives, hypotheses,
/// situation) when there is any, else the existing plan page. A failed read falls back to the existing page too — it has
/// its own states — so a member without the new data (or before the RPCs are applied) never meets a dead end.
struct CarePlanEntryView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let service = dependencies.clientPlan
        Group {
            switch service.state {
            case .loaded(let raw):
                ClientPlanView(raw: raw)
            case .loading:
                VStack(spacing: 0) {
                    CenteredHeader(title: String(localized: "home.healthPlan.title", defaultValue: "My health plan"), hairline: true)
                    FALoadingState(message: String(localized: "careplan.loading", defaultValue: "Loading your plan…"))
                }
                .faWall()
                .toolbar(.hidden, for: .navigationBar)
            case .empty, .failed:
                CarePlanView()
            }
        }
        .task { await service.load() }
    }
}

/// My Plan (mockup `iOSMyPlan`, decisions 2026-11-12), in the mockup's order: the top card with the objectives and their
/// numbers; "Your latest wins"; this week's focus; the actions by moment; the supplements on the plan; the priorities of
/// the week; "Why we're doing this"; "Your situation & evolution"; the next consultation; and the journey for long-term
/// members. Every card is the glass card with a soft colour wash. Every sentence is the practice's (rule 6).
struct ClientPlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    let raw: ClientCarePlanRaw
    @State private var supplements: [CarePlan.Supplement] = []

    var body: some View {
        let habits = dependencies.habits
        let today = ISO8601.dayString(Date())
        let programme = ClientCarePlanLogic.leadProgramme(raw)
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "clientplan.title", defaultValue: "Your plan"), hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let programme { topCard(programme, today: today) }
                    winsCard
                    focusCard
                    actionsCard(habits.plan)
                    supplementsCard
                    prioritiesCard(habits.plan?.priorities ?? [])
                    whyCard
                    situationCard
                    consultationCard(habits.nextCall)
                    journeyCard
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable {
                await dependencies.clientPlan.load(force: true)
                if let request = await dayRequest() { await habits.load(patientId: request.patientId, day: request.day) }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // The actions and the next call ride the Habit Loop's read (Home loads it; a deep link here loads it too).
            await habits.loadNextCall()
            if case .idle = habits.phase, let request = await dayRequest() { await habits.load(patientId: request.patientId, day: request.day) }
            await loadSupplements()
        }
    }

    private func dayRequest() async -> (patientId: String, day: String)? {
        guard let member = try? await dependencies.members.currentMember() else { return nil }
        return (member.patientId, ISO8601.dayString(Date()))
    }

    /// The plan's supplement rows as the practice set them (no observance on this page).
    private func loadSupplements() async {
        guard let member = try? await dependencies.members.currentMember() else { return }
        let loaded = await dependencies.profile.carePlan(patientId: member.patientId)
        supplements = loaded?.supplements ?? []
    }

    // MARK: Top card: programme, phase bar, objectives with their numbers

    private func topCard(_ programme: ClientProgramme, today: String) -> some View {
        let week = ClientCarePlanLogic.week(of: programme, today: today)
        let steps = ClientCarePlanLogic.phaseSteps(programme, week: week)
        let objectives = ClientCarePlanLogic.objectives(raw, programmeId: programme.id)
        return TintedFACard(tint: PlanScreensLogic.bandHex(kind: programme.kind)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(programme.title ?? "").font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let week {
                        Text(ClientPlanFormat.weekText(week, of: ClientCarePlanLogic.totalWeeks(of: programme)))
                            .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(FAColor.forestSoft.opacity(0.16), in: Capsule())
                    }
                }
                if !steps.isEmpty { PhaseBar(steps: steps) }
                if !objectives.isEmpty {
                    Divider()
                    ForEach(objectives) { objective in
                        NavigationLink(value: Route.clientObjective(objective.id)) { ObjectiveNumbers(objective: objective) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Wins, focus, actions, supplements, priorities

    @ViewBuilder
    private var winsCard: some View {
        let wins = Array(ClientCarePlanLogic.wins(raw).prefix(3))
        if !wins.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.wins) {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "clientplan.latestWins", defaultValue: "Your latest wins"))
                    ForEach(wins) { win in
                        HStack(alignment: .top, spacing: 10) {
                            Text(win.achievedAt.map(ClientPlanFormat.shortDate) ?? "")
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).frame(width: 52, alignment: .leading)
                            Text(win.text ?? "").font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var focusCard: some View {
        let habits = dependencies.habits
        let actions: [HabitAction] = habits.plan.map {
            ClientCarePlanLogic.focusActions($0, actions: habits.actions(band: dependencies.focus.focus?.readiness?.bandValue))
        } ?? []
        if !actions.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.focus) {
                VStack(alignment: .leading, spacing: 4) {
                    CPLabel(String(localized: "clientplan.focus", defaultValue: "This week's focus"))
                    ForEach(actions) { action in
                        HStack(spacing: 4) {
                            PlanCheck(done: action.done, title: action.title) { Task { await habits.toggle(action) } }
                            NavigationLink(value: Route.carePlanFocus(action.id)) {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(action.title).font(FATypography.sans(14, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                            .strikethrough(action.done, color: FAColor.inkMuted).multilineTextAlignment(.leading)
                                        if action.streak >= 2 {
                                            Text(String(localized: "clientplan.streak", defaultValue: "\(action.streak)-day streak"))
                                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: PlanCheck.hitSize)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionsCard(_ plan: HabitPlan?) -> some View {
        if let plan, !plan.activeHabits.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.actions) {
                VStack(alignment: .leading, spacing: 12) {
                    CPLabel(String(localized: "clientplan.actions", defaultValue: "My actions"))
                    ForEach(Array(PlanPageLogic.actionsByMoment(plan).enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.slot?.label ?? String(localized: "plan.slot.anytime", defaultValue: "Anytime"))
                                .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestDark)
                            ForEach(group.habits) { habit in
                                let streak = HabitEngine.currentStreak(habit, completions: plan.completions, today: plan.day)
                                NavigationLink(value: Route.carePlanAction(habit.id)) {
                                    HStack(spacing: 8) {
                                        Text(habit.title).font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if streak >= 2 {
                                            Text(String(localized: "clientplan.streak", defaultValue: "\(streak)-day streak"))
                                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                        }
                                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                            .accessibilityHidden(true)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var supplementsCard: some View {
        if !supplements.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.supplements) {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "clientplan.supplements", defaultValue: "Supplements"))
                    ForEach(supplements) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            let detail = [item.dosage, item.timing].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func prioritiesCard(_ priorities: [String]) -> some View {
        let shown = priorities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !shown.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.priorities) {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "clientplan.priorities", defaultValue: "Priorities of the week"))
                    ForEach(shown, id: \.self) { text in
                        Text(text).font(FATypography.sans(14, .medium, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    }
                }
            }
        }
    }

    // MARK: Why, situation and evolution (each row in its signal colour)

    @ViewBuilder
    private var whyCard: some View {
        if !raw.hypotheses.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.forest) {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "clientplan.why", defaultValue: "Why we're doing this"))
                    ForEach(raw.hypotheses) { hypothesis in
                        NavigationLink(value: Route.carePlanWhy) {
                            TintedInsetRow(tint: PlanScreensLogic.signalHex(for: hypothesis.title)) {
                                HStack(spacing: 8) {
                                    Text(hypothesis.title ?? "").font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                                        .foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var situationCard: some View {
        if !raw.complaints.isEmpty {
            TintedFACard(tint: PlanScreensLogic.Tint.forest) {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "clientplan.situation", defaultValue: "Your situation & evolution"))
                    ForEach(raw.complaints) { complaint in
                        NavigationLink(value: Route.carePlanSituation) {
                            TintedInsetRow(tint: PlanScreensLogic.signalHex(for: complaint.signalKey ?? complaint.complaintLabel)) {
                                HStack(spacing: 8) {
                                    Text(ClientCarePlanLogic.name(complaint)).font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                                        .foregroundStyle(FAColor.ink).frame(maxWidth: .infinity, alignment: .leading)
                                    CPStatusPill(status: ClientCarePlanLogic.ComplaintStatus(complaint.status))
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Next consultation and journey

    @ViewBuilder
    private func consultationCard(_ next: AppointmentRow?) -> some View {
        if let next, let start = next.start {
            TintedFACard(tint: PlanScreensLogic.Tint.forest) {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "clientplan.nextConsultation", defaultValue: "Next consultation"))
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    if let link = next.meetingLink, let url = URL(string: link), next.isVideo {
                        Link(destination: url) {
                            Text(String(localized: "clientplan.join", defaultValue: "Join"))
                                .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(.white)
                                .padding(.horizontal, 22).frame(minHeight: FAButton.visualHeight)
                                .background(FAColor.brand, in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                                .frame(minHeight: FAButton.hitHeight)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var journeyCard: some View {
        if ClientCarePlanLogic.showsJourney(raw) {
            FACard {
                CPLinkRow(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "clientplan.journey", defaultValue: "My journey"),
                          detail: String(localized: "clientplan.journey.detail", defaultValue: "All your programmes and wins"), route: .carePlanJourney)
            }
        }
    }
}

/// The soft check for the plan lists: 22pt drawn, 44pt touch target.
struct PlanCheck: View {
    let done: Bool
    let title: String
    let action: () -> Void

    static let visualSize: CGFloat = 22
    static let hitSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: Self.visualSize, weight: .regular))
                .foregroundStyle(done ? FAColor.accent : FAColor.inkMuted)
                .frame(width: Self.visualSize, height: Self.visualSize)
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? String(localized: "plan.check.undo", defaultValue: "Done: \(title). Undo") : String(localized: "plan.check.mark", defaultValue: "Mark done: \(title)"))
    }
}

/// The phases as a bar of segments. My Plan puts "You are here" over the current one; Home shows only the bar.
struct PhaseBar: View {
    let steps: [ClientCarePlanLogic.PhaseStep]
    var showsYouAreHere = true

    var body: some View {
        VStack(spacing: 6) {
            if showsYouAreHere {
                HStack(spacing: 4) {
                    ForEach(steps) { step in
                        Text(step.state == .current ? String(localized: "clientplan.youAreHere", defaultValue: "You are here ▾") : " ")
                            .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.forestDark)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(steps) { step in
                    Capsule().fill(step.state == .upcoming ? FAColor.forestMist.opacity(0.7) : FAColor.accent)
                        .frame(height: 6)
                        .opacity(step.state == .done ? 0.55 : 1)
                }
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(steps) { step in
                    Text(label(step)).font(FATypography.sans(11, step.state == .current ? .semibold : .regular, relativeTo: .caption))
                        .foregroundStyle(step.state == .upcoming ? FAColor.inkSecondary : FAColor.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.map { "\(label($0)), \(stateWord($0.state))" }.joined(separator: ". "))
    }

    private func label(_ step: ClientCarePlanLogic.PhaseStep) -> String {
        let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "\(step.number)" : "\(step.number) · \(title)"
    }

    private func stateWord(_ state: ClientCarePlanLogic.PhaseState) -> String {
        switch state {
        case .done: String(localized: "careplan.phase.done", defaultValue: "done")
        case .current: String(localized: "careplan.phase.current", defaultValue: "in progress")
        case .upcoming: String(localized: "careplan.phase.upcoming", defaultValue: "coming up")
        }
    }
}

/// One objective on My Plan's top card: the member's own words, then each measure with its numbers and bar, all at one
/// size (no icons). The whole block opens the objective.
struct ObjectiveNumbers: View {
    let objective: ClientObjective

    var body: some View {
        let lines = ClientCarePlanLogic.lines(objective)
        let own = ClientCarePlanLogic.usesOwnWords(objective)
        let title = ClientCarePlanLogic.title(objective)
        VStack(alignment: .leading, spacing: 6) {
            Text(own ? "“\(title)”" : title)
                .font(own ? FATypography.display(16, relativeTo: .body) : FATypography.sans(15, .semibold, relativeTo: .body))
                .foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(line.label).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        Spacer(minLength: 8)
                        Text(ClientCarePlanLogic.progressText(line)).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
                    }
                    CPProgressBar(fraction: line.fraction)
                }
                .accessibilityElement(children: .combine)
            }
            if lines.isEmpty, let progress = ClientCarePlanLogic.progress(objective) {
                CPProgressBar(fraction: progress)
            }
            if let next = ClientCarePlanLogic.nextCheck(objective), objective.status != "achieved" {
                Text(String(localized: "clientplan.nextCheck", defaultValue: "Next milestone check \(ClientPlanFormat.shortDate(next))"))
                    .font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
