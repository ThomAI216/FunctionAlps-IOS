import SwiftUI

/// "Curious why?" — the coached-mode education sheet. Member-initiated only (never auto-opens); names the
/// protocol, teaches the mechanism in a no-fault register, closes with "nothing to fix right now".
struct ProtocolWhySheet: View {
    let flag: ProtocolLens.Flag
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(EditableItemList<EmptyView>.capFirst(flag.item)).font(FATypography.sans(16, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
            if let label = ProtocolLens.label(for: flag.protocolKey) {
                Text(label).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
            }
            if let why = ProtocolLens.why(for: flag.protocolKey) {
                Text(why).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
            }
            Text(String(localized: "protocol.why.close", defaultValue: "Nothing to fix right now · just something we’ll explore together."))
                .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button { dismiss() } label: {
                Text(String(localized: "protocol.why.gotIt", defaultValue: "Got it")).font(FATypography.sans(14, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink).padding(.vertical, 8).padding(.horizontal, 16)
            }.buttonStyle(.plain) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FAColor.warm)
    }
}

/// The quiet, neutral marker under a flagged food (never red at capture) — a tap opens the sheet.
struct ProtocolMarker: View {
    let flag: ProtocolLens.Flag
    let onWhy: (ProtocolLens.Flag) -> Void
    var body: some View {
        Button { onWhy(flag) } label: {
            HStack(spacing: 4) {
                Circle().fill(Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.7)).frame(width: 6, height: 6)
                Text(String(localized: "protocol.curiousWhy", defaultValue: "Curious why?")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
            }
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One calm positive line for a clean meal in coached mode.
struct ProtocolFitsLine: View {
    var body: some View {
        Text(String(localized: "protocol.fits", defaultValue: "✓ Fits your protocol"))
            .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

/// The Protocol Lens layer of a meal page: loads the member's protocols once, recomputes the coached flags
/// from the DISPLAYED items (so an edit is reflected at once), owns the sheet. nil flags = layer invisible.
@MainActor
@Observable
final class ProtocolLayer {
    private(set) var flags: [ProtocolLens.Flag]?
    var why: ProtocolLens.Flag?
    private var data: ProtocolData?
    private let protocols: ProtocolService
    private let members: MemberService

    init(protocols: ProtocolService, members: MemberService) {
        self.protocols = protocols
        self.members = members
    }

    func update(items: [MealItem]) async {
        if data == nil {
            guard let member = try? await members.currentMember() else { return }
            data = await protocols.active(patientId: member.patientId)
        }
        guard let data else { return }
        flags = protocols.coachedFlags(items: items.map(\.name), data: data)
    }

    func flag(for item: MealItem) -> ProtocolLens.Flag? { flags?.first { $0.item == item.name } }
}

/// The weekly "Worth a look together" card on Home — the ONLY place aggregated flagged foods reach the member,
/// deferred and collaborative. Hidden in silent mode, with no active protocol, and when the week is clean.
struct ProtocolReviewCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var state: State?
    @State private var expanded = false

    struct State: Equatable {
        let visibility: ProtocolLens.Visibility
        let week: ProtocolLens.Week
        let protocols: [ProtocolLens.PatientProtocol]
    }

    var body: some View {
        Group {
            if let state {
                FACard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "protocol.week.title", defaultValue: "Worth a look together")).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        if state.visibility == .coached {
                            Text(String(localized: "protocol.week.fit", defaultValue: "\(state.week.fitMeals) of \(state.week.totalMeals) meals fit your protocol this week."))
                                .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                        }
                        Text(String(localized: "protocol.week.body", defaultValue: "A few foods this week are worth reviewing together · we’ll look at them at your next session."))
                            .font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                            Text(expanded ? String(localized: "protocol.week.hide", defaultValue: "Hide") : String(localized: "protocol.week.see", defaultValue: "See the foods"))
                                .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                        }
                        .buttonStyle(.plain)
                        if expanded {
                            VStack(spacing: 4) {
                                ForEach(state.week.flaggedFoods.prefix(6)) { food in
                                    HStack {
                                        Text(EditableItemList<EmptyView>.capFirst(food.name)).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                                        Spacer()
                                        Text(foodLine(food, state)).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task { await load() }
    }

    /// Only protocols whose OWN dial is coached are named — a silent/soft protocol's name never appears.
    private func foodLine(_ food: ProtocolLens.Week.Food, _ state: State) -> String {
        let meals = food.count == 1 ? String(localized: "protocol.week.oneMeal", defaultValue: "1 meal") : String(localized: "protocol.week.meals", defaultValue: "\(food.count) meals")
        let names = food.protocols.filter { ProtocolLens.visibility(of: $0, in: state.protocols) == .coached }.compactMap(ProtocolLens.label(for:))
        return names.isEmpty ? meals : meals + " · " + names.joined(separator: ", ")
    }

    private func load() async {
        guard let member = try? await dependencies.members.currentMember() else { state = nil; return }
        let data = await dependencies.protocols.active(patientId: member.patientId)
        let visibility = ProtocolLens.effectiveVisibility(data.protocols)
        guard visibility != .silent else { state = nil; return }
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
        let meals = (try? await dependencies.backend.meals(patientId: member.patientId, since: since)) ?? []
        let week = dependencies.protocols.week(meals: meals, data: data)
        state = week.flaggedFoods.isEmpty ? nil : State(visibility: visibility, week: week, protocols: data.protocols)
    }
}
