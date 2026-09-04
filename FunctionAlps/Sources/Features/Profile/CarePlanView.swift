import SwiftUI

/// The Expo `profile-care-plan.tsx`: header card, Goals, one card per domain section, the update note.
struct CarePlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var plan: CarePlan?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "careplan.title", defaultValue: "My Care Plan"), hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let plan {
                        header(plan)
                        if !plan.goals.isEmpty { goals(plan) }
                        ForEach(plan.sections) { section in sectionCard(section) }
                        Text(String(localized: "careplan.updateNote", defaultValue: "Care plan is updated after each appointment by your practitioner."))
                            .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0x4A8A5C, opacity: 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.3), lineWidth: 1) }
                    } else {
                        FACard {
                            Text(loading
                                 ? String(localized: "careplan.loading", defaultValue: "Loading your plan…")
                                 : String(localized: "careplan.waiting", defaultValue: "Your personalised care plan appears here once your practitioner publishes it after your call."))
                                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let member = try? await dependencies.members.currentMember() {
                plan = await dependencies.profile.carePlan(patientId: member.patientId)
            }
            loading = false
        }
    }

    /// The green header card (the one tinted surface on this page, as on the web).
    private func header(_ plan: CarePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.cream)
                Text(plan.title).font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.cream)
            }
            Text(plan.practitioner + (plan.startDate.isEmpty ? "" : String(localized: "careplan.started", defaultValue: " · Started \(plan.startDate)")))
                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.cream.opacity(0.75))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [FAColor.forestSoft, FAColor.forest], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.bottom, 20)
    }

    private func goals(_ plan: CarePlan) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "target").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    Text(String(localized: "careplan.goals", defaultValue: "Goals")).font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                }
                .padding(.bottom, 4)
                ForEach(plan.goals, id: \.self) { goal in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6).padding(.top, 6)
                        Text(goal).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5)
                    }
                }
            }
        }
        .padding(.bottom, 14)
    }

    private func sectionCard(_ section: CarePlan.Section) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: section.colorHex, opacity: 0.13))
                        Image(systemName: section.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: section.colorHex))
                    }
                    .frame(width: 32, height: 32)
                    Text(section.category).font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                }
                .padding(.bottom, 12)
                ForEach(Array(section.items.enumerated()), id: \.element.id) { idx, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.status == .completed ? "checkmark.circle" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(item.status == .completed ? FAColor.forestSoft : ProfilePalette.muted)
                            .padding(.top, 2)
                        Text(item.text).font(FATypography.sans(13, relativeTo: .subheadline))
                            .foregroundStyle(item.status == .paused ? ProfilePalette.muted : FAColor.ink).lineSpacing(5)
                    }
                    .padding(.bottom, idx < section.items.count - 1 ? 10 : 0)
                    .overlay(alignment: .bottom) {
                        if idx < section.items.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                    }
                    .padding(.bottom, idx < section.items.count - 1 ? 10 : 0)
                }
            }
        }
        .padding(.bottom, 12)
    }
}
