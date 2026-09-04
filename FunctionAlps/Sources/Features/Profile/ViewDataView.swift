import SwiftUI

/// "Your data" (the Expo `privacy-view-data.tsx`): the profile bits, what we hold (counts per table),
/// the three most recent meals, and the read-only footnote.
struct ViewDataView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var summary: DataSummary?
    @State private var loading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: String(localized: "data.title", defaultValue: "Your data"))
                if loading {
                    VStack(spacing: 12) {
                        ProgressView().tint(ProfilePalette.muted)
                        Text(String(localized: "state.loading", defaultValue: "Loading…")).font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else if let summary {
                    section(String(localized: "data.profile", defaultValue: "Profile")) {
                        SurfaceCard {
                            VStack(spacing: 0) {
                                row(String(localized: "data.name", defaultValue: "Name"), summary.profileName ?? "·")
                                row(String(localized: "profile.age", defaultValue: "Age"), summary.age.map { "\($0)" } ?? "·")
                                row(String(localized: "data.sex", defaultValue: "Sex"), summary.sex ?? "·")
                                row(String(localized: "data.goals", defaultValue: "Goals"), summary.goals.isEmpty ? "·" : summary.goals.joined(separator: ", "))
                                row(String(localized: "data.diet", defaultValue: "Dietary pattern"), summary.dietaryPattern ?? "·", last: true)
                            }
                        }
                    }
                    section(String(localized: "data.hold", defaultValue: "What we hold")) {
                        SurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(summary.counts.enumerated()), id: \.element.id) { i, c in
                                    row(c.label, "\(c.value)", last: i == summary.counts.count - 1)
                                }
                            }
                        }
                    }
                    if !summary.recentMeals.isEmpty {
                        section(String(localized: "data.recentMeals", defaultValue: "Recent meals")) {
                            SurfaceCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(summary.recentMeals.enumerated()), id: \.element.id) { i, m in
                                        HStack {
                                            Text(m.name).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                            Text(m.loggedAt.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "·").font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                                        }
                                        .padding(.vertical, 10)
                                        .overlay(alignment: .bottom) { if i < summary.recentMeals.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
                                    }
                                }
                            }
                        }
                    }
                    Text(String(localized: "data.footnote", defaultValue: "This is a read-only view of your stored data.\nTo request deletion, visit Privacy & data settings."))
                        .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(4)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 6) {
                        Text(String(localized: "data.none.title", defaultValue: "No data yet")).font(FATypography.sans(15, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "data.none.body", defaultValue: "Once you start logging meals and check-ins,\nyour data will appear here.")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).multilineTextAlignment(.center).lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let member = try? await dependencies.members.currentMember() {
                summary = await dependencies.account.dataSummary(member: member)
            }
            loading = false
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
                .padding(.horizontal, 2).padding(.bottom, 10)
            content()
        }
        .padding(.bottom, 24)
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
            Spacer()
            Text(value).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
    }
}

/// One legal document (the Expo `legal/*.tsx`), read from CM OS `consent_definitions` so the wording has
/// exactly one author. Falls back to English when the member's language is not seeded yet.
struct LegalDocumentView: View {
    let key: String
    @Environment(AppDependencies.self) private var dependencies
    @State private var document: LegalDocument?
    @State private var loading = true

    private var fallbackTitle: String {
        switch key {
        case "terms_of_use": String(localized: "legal.terms", defaultValue: "Terms")
        case "legal_notice": String(localized: "legal.notice", defaultValue: "Legal Notice")
        default: String(localized: "legal.privacy", defaultValue: "Privacy Policy")
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: document?.title ?? fallbackTitle)
                if let document {
                    ReadingSurface {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(localized: "legal.version", defaultValue: "Version \(document.version)"))
                                .font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted).padding(.bottom, 10)
                            LegalMarkdownView(markdown: document.bodyMd)
                        }
                    }
                } else if loading {
                    ProgressView().tint(FAColor.forestSoft).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ReadingSurface {
                        Text(String(localized: "legal.unavailable", defaultValue: "This document couldn't be loaded right now. Check your connection and try again, or write to data@functionalps.ch."))
                            .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            document = try? await dependencies.account.legalDocument(key: key)
            loading = false
        }
    }
}
