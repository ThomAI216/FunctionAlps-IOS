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

/// The Plan page (mockup `iOSPlan`): programme and phase bar with "you are here", the goals in the client's words with
/// milestone progress, the actions by moment, the next consultation, and the rows to "Why we're doing this" and
/// "Your situation & evolution". Every sentence is the practice's (rule 6).
struct ClientPlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    let raw: ClientCarePlanRaw

    var body: some View {
        let habits = dependencies.habits
        let today = ISO8601.dayString(Date())
        let programme = ClientCarePlanLogic.leadProgramme(raw)
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "clientplan.title", defaultValue: "Your plan"), hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let programme { programmeCard(programme, today: today) }
                    objectivesCard(programme: programme)
                    actionsCard(habits.plan)
                    consultationCard(habits.nextCall)
                    explainerCard
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
        }
    }

    private func dayRequest() async -> (patientId: String, day: String)? {
        guard let member = try? await dependencies.members.currentMember() else { return nil }
        return (member.patientId, ISO8601.dayString(Date()))
    }

    // MARK: Programme and phase bar

    private func programmeCard(_ programme: ClientProgramme, today: String) -> some View {
        let week = ClientCarePlanLogic.week(of: programme, today: today)
        let steps = ClientCarePlanLogic.phaseSteps(programme, week: week)
        return FACard {
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
                if ClientCarePlanLogic.showsJourney(raw) {
                    Divider()
                    CPLinkRow(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: String(localized: "clientplan.journey", defaultValue: "My journey"),
                              detail: String(localized: "clientplan.journey.detail", defaultValue: "All your programmes and wins"), route: .carePlanJourney)
                }
            }
        }
    }

    // MARK: Objectives

    @ViewBuilder
    private func objectivesCard(programme: ClientProgramme?) -> some View {
        let objectives = ClientCarePlanLogic.objectives(raw, programmeId: programme?.id)
        if !objectives.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 14) {
                    CPLabel(String(localized: "clientplan.goals", defaultValue: "My goals · in my words"))
                    ForEach(objectives) { objective in
                        NavigationLink(value: Route.clientObjective(objective.id)) { ObjectiveSummary(objective: objective) }
                            .buttonStyle(.plain)
                        if objective.id != objectives.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: Actions by moment

    @ViewBuilder
    private func actionsCard(_ plan: HabitPlan?) -> some View {
        if let plan, !plan.activeHabits.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    CPLabel(String(localized: "clientplan.actions", defaultValue: "My actions"))
                    ForEach(Array(PlanPageLogic.actionsByMoment(plan).enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.slot?.label ?? String(localized: "plan.slot.anytime", defaultValue: "Anytime"))
                                .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestDark)
                            ForEach(group.habits) { habit in
                                let streak = HabitEngine.currentStreak(habit, completions: plan.completions, today: plan.day)
                                NavigationLink(value: Route.action(habit.id)) {
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
                                    .frame(minHeight: 40)
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

    // MARK: Next consultation

    @ViewBuilder
    private func consultationCard(_ next: AppointmentRow?) -> some View {
        if let next, let start = next.start {
            FACard {
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

    // MARK: "Why we're doing this" and "Your situation & evolution"

    @ViewBuilder
    private var explainerCard: some View {
        let why = raw.hypotheses.count
        let hasSituation = !raw.complaints.isEmpty || !raw.situation.isEmpty
        if why > 0 || hasSituation {
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    if why > 0 {
                        CPLinkRow(symbol: "lightbulb", title: String(localized: "clientplan.why", defaultValue: "Why we're doing this"),
                                  detail: String(localized: "clientplan.why.detail", defaultValue: "What is behind your plan"), route: .carePlanWhy)
                    }
                    if why > 0 && hasSituation { Divider() }
                    if hasSituation {
                        CPLinkRow(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "clientplan.situation", defaultValue: "Your situation & evolution"),
                                  detail: String(localized: "clientplan.situation.detail", defaultValue: "Where you started and how it is changing"), route: .carePlanSituation)
                    }
                }
            }
        }
    }
}

/// The phases as a bar of segments with "You are here" over the current one.
struct PhaseBar: View {
    let steps: [ClientCarePlanLogic.PhaseStep]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(steps) { step in
                    Text(step.state == .current ? String(localized: "clientplan.youAreHere", defaultValue: "You are here ▾") : " ")
                        .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.forestDark)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

/// One objective on the Plan page: the member's own words, its milestones as thin bars, the next check.
struct ObjectiveSummary: View {
    let objective: ClientObjective

    var body: some View {
        let lines = ClientCarePlanLogic.lines(objective)
        let own = ClientCarePlanLogic.usesOwnWords(objective)
        let title = ClientCarePlanLogic.title(objective)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(own ? "“\(title)”" : title)
                    .font(own ? FATypography.display(18, relativeTo: .title3) : FATypography.sans(15, .semibold, relativeTo: .headline))
                    .foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if objective.status == "achieved" {
                    Label(String(localized: "clientplan.achieved", defaultValue: "Achieved"), systemImage: "checkmark.circle.fill")
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(line.label).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                        Spacer(minLength: 8)
                        Text(ClientCarePlanLogic.progressText(line)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
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
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}
