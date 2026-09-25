import SwiftUI

/// The member's released lab results, newest first (the Expo `results/index.tsx`). Each card opens
/// the full result. Reads `LabResultsService` — the same load the result and the marker sheet use.
struct LabResultsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    var body: some View {
        let labs = dependencies.labs
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "labs.title", defaultValue: "Lab results"), hairline: true)
            switch labs.state {
            case .loading:
                LabStates.loading
            case .failed(let error):
                LabStates.failed(error) { Task { await labs.load(force: true) } }
            case .empty:
                ScrollView(showsIndicators: false) {
                    LabStates.empty.padding(16).padding(.bottom, FASpacing.navBarClearance)
                }
                .refreshable { await labs.load(force: true) }
            case .loaded(let results):
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            ReleaseCard(result: result, latest: index == 0) { router.push(.labResult(result.releaseId)) }
                        }
                        Text(String(localized: "labs.list.note", defaultValue: "Results are reviewed by your FunctionAlps nutritionist before they are shared with you."))
                            .font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                            .multilineTextAlignment(.center).lineSpacing(3)
                            .frame(maxWidth: .infinity).padding(.top, 6)
                    }
                    .padding(16)
                    .padding(.bottom, FASpacing.navBarClearance)
                }
                .refreshable { await labs.load(force: true) }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await labs.load() }
    }
}

/// A released result in the list: its date, its headline, and how many lines sit in each state.
private struct ReleaseCard: View {
    let result: LabResult
    let latest: Bool
    let action: () -> Void

    private static let order: [LabMarkerStatus] = [.outOfRange, .watch, .inRange]

    var body: some View {
        let copy = LabResultCopy.forLanguage(result.language)
        let counts = LabResultsLogic.counts(result.markers)
        Button(action: action) {
            FACard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x4A8A5C, opacity: 0.13))
                        Image(systemName: "testtube.2").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(LabSampleDate.format(result.sampledAt, language: result.language))
                            .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        Text(result.headline)
                            .font(FATypography.sans(15, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            .multilineTextAlignment(.leading).lineSpacing(3).padding(.top, 2)
                        FlowLayout(spacing: 8) {
                            ForEach(Self.order.filter { (counts[$0] ?? 0) > 0 }, id: \.self) { status in
                                HStack(spacing: 4) {
                                    LabStatusBadge(status: status, copy: copy)
                                    Text("\(counts[status] ?? 0)").font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 8)
                }
            }
            .overlay {
                if latest {
                    RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                        .strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
