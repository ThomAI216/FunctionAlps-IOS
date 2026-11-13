import SwiftUI

/// "Supplements" on the Plan page (mockup `iOSMyPlan`): each supplement with its dose and moment, why it is in the
/// plan, how regularly it was taken — written first ("11 of 14 days · 79%"), with a thin bar whose colour is only
/// an accent — and a way into its page.
///
/// States (rule 5): while the first read is in flight and when the member has no supplements the card holds no place;
/// a failed read says so, with a retry; a refresh keeps the rows.
struct SupplementsPlanCard: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let service = dependencies.supplements
        Group {
            switch service.phase {
            case .idle, .loading:
                EmptyView()
            case .failed(let message):
                FACard {
                    FAErrorState(title: String(localized: "supp.error.title", defaultValue: "Couldn't load your supplements"), message: message) {
                        Task { await service.retry() }
                    }
                }
            case .loaded(let list):
                if !list.isEmpty {
                    FACard {
                        VStack(alignment: .leading, spacing: 14) {
                            CPLabel(String(localized: "supp.plan.title", defaultValue: "Supplements"))
                            let ordered = SupplementLogic.planOrder(list)
                            ForEach(ordered) { s in
                                NavigationLink(value: Route.supplement(s.id)) { row(s) }
                                    .buttonStyle(.plain)
                                if s.id != ordered.last?.id { Divider().overlay(ProfilePalette.hairline) }
                            }
                        }
                    }
                }
            }
        }
        .task { if case .idle = service.phase { await service.load() } }
    }

    private func row(_ s: Supplement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SupplementIcon()
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(FATypography.headline).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                Text(SupplementLogic.doseLine(s)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                if !s.isActive {
                    Label(String(localized: "supp.paused", defaultValue: "Paused"), systemImage: "pause.circle")
                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
                if let why = s.why?.trimmingCharacters(in: .whitespacesAndNewlines), !why.isEmpty {
                    Text(why).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if s.isActive { SupplementAdherenceLine(supplement: s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                .padding(.top, 6).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
