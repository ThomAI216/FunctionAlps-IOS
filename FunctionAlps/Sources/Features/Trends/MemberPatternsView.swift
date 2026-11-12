import SwiftUI

/// The patterns a practitioner has reviewed and shared (`nb_user_patterns`; RLS returns only validated rows).
/// Each is a count from the member's own logs — "On 4 of 5 days with a late dinner, your energy the next day was
/// lower than on other days." — never a diagnosis, and nothing the practitioner has not released appears.
struct MemberPatternsView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let trends = dependencies.trends
        ZStack {
            if let page = trends.page {
                content(page)
            } else if case .failed(let message) = trends.phase {
                FAErrorState(title: String(localized: "trends.error.load", defaultValue: "Couldn't load your trends"), message: message) {
                    Task { await trends.load() }
                }
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await trends.loadIfNeeded() }
    }

    private func content(_ page: TrendsEngine.Page) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                TrendDetailHeader(title: String(localized: "trends.patterns.title", defaultValue: "Patterns")) {
                    Text(String(localized: "trends.patterns.intro", defaultValue: "Shared by your practitioner after review. These are counts from your own logs, not diagnoses."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if page.patterns.isEmpty {
                    FACard {
                        FAEmptyState(
                            title: String(localized: "trends.patterns.empty.title", defaultValue: "Nothing shared yet"),
                            message: String(localized: "trends.patterns.empty", defaultValue: "Your practitioner hasn't shared any patterns with you yet."),
                            systemImage: "text.magnifyingglass")
                    }
                } else {
                    ForEach(page.patterns) { pattern in card(pattern) }
                }
                Text(String(localized: "trends.patterns.note", defaultValue: "Only what your practitioner has reviewed and shared appears here."))
                    .font(FATypography.sans(11.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkMuted)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
    }

    private func card(_ pattern: SharedPattern) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(pattern.title)
                    .font(FATypography.display(21, relativeTo: .title3))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pattern.sentence)
                    .font(FATypography.sans(14.5, relativeTo: .callout))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let shared = pattern.sharedAt {
                    Divider().overlay(Color.white.opacity(0.7))
                    let date = shared.formatted(.dateTime.day().month(.abbreviated))
                    Text(String(localized: "trends.patterns.shared", defaultValue: "Shared \(date) by your practitioner"))
                        .font(FATypography.sans(11.5, relativeTo: .caption))
                        .foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
