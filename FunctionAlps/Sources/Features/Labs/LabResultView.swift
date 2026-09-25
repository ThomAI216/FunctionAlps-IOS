import SwiftUI

/// One released result, rendered verbatim from the release (the Expo `results/[releaseId].tsx` and
/// mockup 05-member-results): headline, the three short blocks, the phase card when the plan moved,
/// the marker lines — flagged first, in-range folded — and the next steps. Nothing is rephrased,
/// computed or coloured from a number here; the release says it in words, in its own language.
struct LabResultView: View {
    let releaseId: String
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    /// nil = not touched yet: open when there is nothing flagged, folded when there is.
    @State private var inRangeOpen: Bool?

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
                scroll(labs) { LabStates.missing }
            case .loaded:
                if let result = labs.result(releaseId) {
                    scroll(labs) { content(result) }
                } else {
                    scroll(labs) { LabStates.missing }
                }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await labs.load() }
    }

    private func scroll<Content: View>(_ labs: LabResultsService, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
        }
        .refreshable { await labs.load(force: true) }
    }

    private func content(_ result: LabResult) -> some View {
        let t = LabResultCopy.forLanguage(result.language)
        let split = LabResultsLogic.split(result.markers)
        let open = inRangeOpen ?? split.flagged.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            // Headline
            VStack(alignment: .leading, spacing: 4) {
                Text(LabSampleDate.format(result.sampledAt, language: result.language))
                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                Text(result.headline)
                    .font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.forest).lineSpacing(3)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield").font(.system(size: 13, weight: .semibold))
                    Text(t.validated).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                }
                .foregroundStyle(FAColor.forestSoft)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            LabBlockCard(title: t.saw, text: result.whatWeSaw)
            LabBlockCard(title: t.means, text: result.whatItMeans)
            LabBlockCard(title: t.next, text: result.whatWeDoNext)

            if let phase = result.phaseUpdate {
                FACard {
                    VStack(alignment: .leading, spacing: 6) {
                        LabKicker(t.phase, tinted: true)
                        Text(phase.title).font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(phase.summary).font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                        .strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.35), lineWidth: 1)
                }
            }

            // The lines: flagged first, the calm ones behind one fold
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    LabKicker(t.lines).padding(.bottom, 4)
                    ForEach(Array(split.flagged.enumerated()), id: \.element.id) { index, marker in
                        LabMarkerRow(marker: marker, copy: t, first: index == 0) { openMarker(result, marker) }
                    }
                    if !split.inRange.isEmpty {
                        Button { inRangeOpen = !open } label: {
                            HStack {
                                Text(t.inRange(split.inRange.count)).font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                                Spacer()
                                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(FAColor.forestSoft)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if !split.flagged.isEmpty { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(open ? String(localized: "labs.a11y.expanded", defaultValue: "Expanded") : String(localized: "labs.a11y.collapsed", defaultValue: "Collapsed"))
                        if open {
                            ForEach(split.inRange) { marker in
                                LabMarkerRow(marker: marker, copy: t) { openMarker(result, marker) }
                            }
                        }
                    }
                }
            }

            if !result.nextSteps.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 8) {
                        LabKicker(t.steps)
                        ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { _, step in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6).padding(.top, 8)
                                Text(step.statement).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                            }
                        }
                    }
                }
            }

            LabAskButton(copy: t).padding(.top, 6)
            LabFootnote(text: t.disclaimer)
        }
    }

    private func openMarker(_ result: LabResult, _ marker: LabMarker) {
        router.push(.labMarker(releaseId: result.releaseId, markerId: marker.id))
    }
}
