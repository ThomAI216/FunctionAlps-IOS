import SwiftUI
import Observation

/// Gut Intelligence — the Expo `gut-intelligence.tsx` minus the broken "digestion signals" tile: the
/// score with its three factors and 14-day bars, what your gut likes, today's reads, the compass, and
/// the way into the check-in.
struct GutIntelligenceView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: GutIntelligenceViewModel?
    private static let tint = Color(hex: 0x86B8A6)
    private static let bad = Color(hex: 0xC2554C)

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "gut.dash.title", defaultValue: "Gut Intelligence"))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let model, let d = model.dashboard {
                        scoreCard(d)
                        likesCard(d)
                        todayCard(d, done: model.doneToday)
                        compassCard
                    } else if let model, let error = model.errorMessage {
                        FAErrorState(title: String(localized: "gut.dash.error", defaultValue: "Couldn't load your gut data"), message: error) { Task { await model.load() } }
                    } else {
                        FALoadingState()
                    }
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = GutIntelligenceViewModel(gut: dependencies.gut, members: dependencies.members, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
        .onAppear { if let model, model.dashboard != nil { Task { await model.load() } } }
    }

    private func scoreCard(_ d: GutService.Dashboard) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(d.score.map(String.init) ?? "·").font(FATypography.sans(40, .bold, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).monospacedDigit()
                        Text("/100").font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                    }
                    Spacer()
                    if let score = d.score { statusPill(GutEngine.status(score)) }
                }
                ForEach(d.factors.filter { $0.value != nil }) { f in
                    HStack(spacing: 9) {
                        Text(f.label).font(FATypography.sans(11.5, .medium, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineLimit(1).frame(width: 110, alignment: .leading)
                        HashedBar(color: Self.tint, pct: Double(f.value ?? 0) / 100, height: 9, raised: true)
                        Text(f.value.map(String.init) ?? "·").font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.ink).frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                if d.series.contains(where: { $0 != nil }) {
                    ScoreBarTrend(values: d.series, color: Self.tint, height: 84)
                    Text(String(localized: "gut.dash.last14", defaultValue: "Last 14 days")).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
                } else {
                    Text(String(localized: "gut.dash.noScore", defaultValue: "Do a gut check-in or rate a meal and your score appears here.")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4)
                }
            }
        }
    }

    private func statusPill(_ s: GutEngine.Status) -> some View {
        let (label, color): (String, Color) = switch s {
        case .onTrack: (String(localized: "gut.status.onTrack", defaultValue: "On track"), Color(hex: 0x4A8A5C))
        case .needsSupport: (String(localized: "gut.status.needsSupport", defaultValue: "Needs support"), Color(hex: 0xD97706))
        case .watchClosely: (String(localized: "gut.status.watch", defaultValue: "Watch closely"), Color(hex: 0xDC2626))
        }
        return Text(label).font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.15), in: Capsule())
    }

    private func likesCard(_ d: GutService.Dashboard) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "gut.likes.title", defaultValue: "What your gut likes")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                Text(String(localized: "gut.likes.sub", defaultValue: "Foods linked to how your meals felt afterwards.")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                if d.liked.isEmpty && d.disliked.isEmpty {
                    Text(String(localized: "gut.likes.empty", defaultValue: "Log a few meals and how they felt, and your food · feeling patterns appear here.")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4)
                } else {
                    if !d.liked.isEmpty { chips(String(localized: "gut.likes.good", defaultValue: "Sat well"), d.liked, Color(hex: 0x4A8A5C)) }
                    if !d.disliked.isEmpty { chips(String(localized: "gut.likes.bad", defaultValue: "Didn't sit well"), d.disliked, Self.bad) }
                }
            }
        }
    }

    private func chips(_ title: String, _ names: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(color)
            FlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Text(name).font(FATypography.sans(12, .medium, relativeTo: .caption)).foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.14), in: Capsule())
                }
            }
        }
    }

    private func todayCard(_ d: GutService.Dashboard, done: Bool) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "gut.today.title", defaultValue: "Today's digestion reads")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                if let reads = d.todayReads {
                    HStack(spacing: 8) {
                        readTile(String(localized: "gut.factor.comfort", defaultValue: "Digestion comfort"), reads.comfort)
                        readTile(String(localized: "gut.stool.title", defaultValue: "Stool"), reads.stool)
                        readTile(String(localized: "gut.reactions.title", defaultValue: "Food reactions"), reads.reactions)
                    }
                } else {
                    Text("···").font(FATypography.sans(28, relativeTo: .title)).foregroundStyle(FAColor.inkMuted).tracking(8)
                    Text(String(localized: "gut.today.empty", defaultValue: "Do your gut check-in to start tracking your digestion here.")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4)
                }
                NavigationLink(value: Route.gutCheckin) {
                    Text(done ? String(localized: "gut.today.edit", defaultValue: "Edit today's check-in") : String(localized: "gut.today.assess", defaultValue: "Assess today's digestion"))
                        .font(FATypography.sans(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(FAColor.brand.opacity(0.22), in: Capsule())
                        .overlay(Capsule().strokeBorder(FAColor.brand.opacity(0.55), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                if done {
                    Text(String(localized: "gut.today.again", defaultValue: "You can reassess again today if things changed.")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(Color(hex: 0x4A8A5C))
                }
            }
        }
    }

    private func readTile(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map(String.init) ?? "·").font(FATypography.sans(20, .bold, relativeTo: .title2)).foregroundStyle(value.map { FunctionalSliderView.ramp[CheckinEngine.stateRampIndex(Double($0))] } ?? FAColor.inkMuted).monospacedDigit()
            Text(label).font(FATypography.sans(10.5, .medium, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var compassCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "gut.compass.title", defaultValue: "What tends to move this")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                Text(String(localized: "gut.compass.tells", defaultValue: "How comfortable and tolerant your gut feels · daily comfort, how meals sit afterwards, and stool regularity."))
                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        String(localized: "gut.compass.l1", defaultValue: "Spot your trigger foods"),
                        String(localized: "gut.compass.l2", defaultValue: "Right portions, slower eating"),
                        String(localized: "gut.compass.l3", defaultValue: "Fibre + hydration"),
                        String(localized: "gut.compass.l4", defaultValue: "Lower mealtime stress"),
                    ], id: \.self) { lever in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Self.tint).frame(width: 6, height: 6).padding(.top, 6)
                            Text(lever).font(FATypography.sans(13, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        }
                    }
                }
                Text(String(localized: "gut.compass.science", defaultValue: "From your gut check-ins and how meals felt afterwards. A comfort compass, not a diagnosis."))
                    .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkMuted).italic().lineSpacing(3)
            }
        }
    }
}

@MainActor
@Observable
final class GutIntelligenceViewModel {
    private(set) var dashboard: GutService.Dashboard?
    private(set) var doneToday = false
    var errorMessage: String?
    private let gut: GutService
    private let members: MemberService
    private let auth: AuthService

    init(gut: GutService, members: MemberService, auth: AuthService) { self.gut = gut; self.members = members; self.auth = auth }

    func load() async {
        do {
            let member = try await members.currentMember()
            let state = try await gut.load(patientId: member.patientId)
            dashboard = gut.dashboard(state)
            doneToday = state.today != nil
            errorMessage = nil
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "gut.dashboard")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if dashboard == nil { errorMessage = error.userMessage }
        } catch {
            if dashboard == nil { errorMessage = String(describing: error) }
        }
    }
}
