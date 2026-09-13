import SwiftUI

/// "Your Scores" — the Expo `(screens)/scores.tsx`: the Functional Score hero, the meal trio from what the
/// member logs, the three pillars + Gut Intelligence, the four body signals from the check-in, the three gut
/// signals from the gut check-in. Every tile opens the page that explains that number; the app renders,
/// it never scores (the composite comes from `member-scores`, the meal averages from the logged rows).
struct ScoresHubView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScoresHubModel?
    @State private var explaining: MealScoreKind?

    private static let functionalTint = Color(hex: 0x8FBF97)
    private static let gutTint = Color(hex: 0x86B8A6)
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Text("‹ " + String(localized: "scores.back", defaultValue: "Back"))
                        .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                Text(String(localized: "scores.title", defaultValue: "Your Scores")).font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink)
                Text(String(localized: "scores.subtitle", defaultValue: "What we measure, what it means, and how to move it"))
                    .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).padding(.top, 2)

                if let model {
                    hero(model)
                    section(String(localized: "scores.section.meal", defaultValue: "Meal scores · from what you log"))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(MealScoreKind.allCases) { kind in
                            let m = model.meal[kind]
                            ScoreHubTile(score: m?.avg, label: kind.title, tint: kind.color, trend: m?.trend) { explaining = kind }
                        }
                    }
                    section(String(localized: "scores.section.pillars", defaultValue: "Functional pillars"))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(MemberScores.Pillar.allCases, id: \.self) { pillar in
                            ScoreHubTile(score: model.scores?.breakdown(pillar).intScore, label: pillar.title, tint: Color(hex: pillar.tintHex)) {
                                router.openTrends(pillar: pillar)
                            }
                        }
                        ScoreHubTile(score: model.scores?.gut.intScore, label: String(localized: "scores.gut", defaultValue: "Gut Intelligence"), tint: Self.gutTint) {
                            router.push(.gutIntelligence)
                        }
                    }
                    section(String(localized: "scores.section.body", defaultValue: "Body signals · from your check-in"))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(BodySignal.allCases) { s in
                            ScoreHubTile(score: model.body[s]?.score, label: s.title, tint: s.tint) { router.push(.bodySignal(s)) }
                        }
                    }
                    section(String(localized: "scores.section.gut", defaultValue: "Gut signals · from your gut check-in"))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(GutSignal.allCases) { s in
                            ScoreHubTile(score: model.gut[s]?.score, label: s.short, tint: s.tint) { router.push(.gutSignal(s)) }
                        }
                    }
                } else {
                    FALoadingState().padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = ScoresHubModel(dependencies: dependencies)
                await m.load()
                model = m
            }
        }
        .refreshable { await model?.load() }
        .sheet(item: $explaining) { kind in
            ScoreExplainerView(kind: kind).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private func hero(_ model: ScoresHubModel) -> some View {
        Button { router.openTrends(pillar: nil) } label: {
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "scores.functional.kicker", defaultValue: "◆ Functional Score").uppercased())
                            .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(1).foregroundStyle(Self.functionalTint)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.scores?.composite.intScore.map(String.init) ?? "·").font(FATypography.display(44, relativeTo: .largeTitle)).foregroundStyle(Self.functionalTint)
                        Text(String(localized: "scores.functional.caption", defaultValue: "/100 · your day in one read")).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                    }
                    .padding(.top, 6)
                    ScoreBarTrend(values: model.scores?.crownSeries ?? [], color: Self.functionalTint, height: 70).padding(.top, 12)
                    Text(String(localized: "scores.functional.foot", defaultValue: "Vitality · Metabolic · Nutrition, blended · tap to learn how to steer by it"))
                        .font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).padding(.top, 7)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    private func section(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
            .padding(.top, 22).padding(.bottom, 11)
    }
}

/// One score in the hub: ring (or · when no data) + label + status + chevron. The whole tile is the button.
struct ScoreHubTile: View {
    let score: Int?
    let label: String
    let tint: Color
    var trend: ScoreHistory.Trend? = nil
    let onPress: () -> Void

    private var arrow: String {
        switch trend {
        case .up: " ▲"
        case .down: " ▼"
        case .flat: " →"
        case nil: ""
        }
    }

    var body: some View {
        Button(action: onPress) {
            FACard {
                HStack(spacing: 10) {
                    if let score {
                        ScoreWheel(value: score, color: tint, size: 46, track: tint.opacity(0.15))
                    } else {
                        Circle().strokeBorder(FAColor.separator, lineWidth: 3.2).frame(width: 46, height: 46)
                            .overlay { Text("·").font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.ink).lineLimit(1)
                        let status = ScoreStatus.of(score)
                        Text(score == nil ? String(localized: "scores.tile.empty", defaultValue: "Log to see") : status.label + arrow)
                            .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(score == nil ? FAColor.inkSecondary : status.color).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(score.map { "\(label): \($0) out of 100" } ?? label)
    }
}

/// Loads the four sources once: member-scores, the logged meals, 14 days of check-ins, 14 days of gut days.
@MainActor
@Observable
final class ScoresHubModel {
    private(set) var scores: MemberScores?
    private(set) var meal: [MealScoreKind: ScoresOverview.MealSummary] = [:]
    private(set) var body: [BodySignal: ScoresOverview.Signal] = [:]
    private(set) var gut: [GutSignal: ScoresOverview.Signal] = [:]
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func load() async {
        let calendar = Calendar.current
        let now = Date()
        let offset = calendar.timeZone.secondsFromGMT(for: now) / 60
        let backend = dependencies.backend
        let meals = dependencies.meals
        async let scoresRead = backend.memberScores(tzOffsetMinutes: offset)
        if let member = try? await dependencies.members.currentMember() {
            let since = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
            let sinceDay = ISO8601.dayString(since, calendar: calendar)
            let today = ISO8601.dayString(now, calendar: calendar)
            async let mealsRead = meals.recentMeals(patientId: member.patientId)
            async let checkinsRead = backend.dailyCheckins(patientId: member.patientId, since: sinceDay)
            async let gutRead = backend.gutHistory(patientId: member.patientId, since: sinceDay, before: today)
            async let gutToday = backend.gutToday(patientId: member.patientId, day: today)
            let mealRows = (try? await mealsRead) ?? []
            let checkins = (try? await checkinsRead) ?? []
            var gutDays = (try? await gutRead) ?? []
            if let t = try? await gutToday { gutDays.append(t.day) }
            meal = Dictionary(uniqueKeysWithValues: MealScoreKind.allCases.map { ($0, ScoresOverview.meal($0, meals: mealRows, now: now, calendar: calendar)) })
            body = Dictionary(uniqueKeysWithValues: BodySignal.allCases.map { ($0, ScoresOverview.body($0, checkins: checkins, now: now, calendar: calendar)) })
            gut = Dictionary(uniqueKeysWithValues: GutSignal.allCases.map { ($0, ScoresOverview.gut($0, days: gutDays, now: now, calendar: calendar)) })
        }
        scores = try? await scoresRead
    }
}
