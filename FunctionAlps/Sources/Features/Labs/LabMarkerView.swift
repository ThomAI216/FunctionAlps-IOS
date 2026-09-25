import SwiftUI

/// One released marker line, opened (the Expo `biomarkers/[markerId].tsx`, mockup 06-member-marker):
/// the value as the lab printed it, its status (icon + label), why it matters, the explanation, what
/// the plan does about it, and the same marker in earlier released results.
///
/// Not rendered on purpose: a range band. The member contract carries no ranges, and drawing one
/// here would mean computing a clinical position on the phone — the release says it in words.
struct LabMarkerView: View {
    let releaseId: String
    let markerId: String
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let labs = dependencies.labs
        let result = labs.result(releaseId)
        let marker = result?.markers.first { $0.id == markerId }
        VStack(spacing: 0) {
            CenteredHeader(title: marker?.label ?? String(localized: "labs.title", defaultValue: "Lab results"), hairline: true)
            switch labs.state {
            case .loading:
                LabStates.loading
            case .failed(let error):
                LabStates.failed(error) { Task { await labs.load(force: true) } }
            case .empty, .loaded:
                ScrollView(showsIndicators: false) {
                    Group {
                        if let result, let marker {
                            content(result, marker, history: LabResultsLogic.earlierValues(in: labs.results, releaseId: releaseId, label: marker.label))
                        } else {
                            LabStates.missing
                        }
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

    private func content(_ result: LabResult, _ marker: LabMarker, history: [LabEarlierValue]) -> some View {
        let t = LabResultCopy.forLanguage(result.language)
        return VStack(alignment: .leading, spacing: 10) {
            FACard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LabSampleDate.format(result.sampledAt, language: result.language))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                    Text(marker.label)
                        .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker.value).font(FATypography.display(34, relativeTo: .largeTitle)).foregroundStyle(FAColor.forest)
                        if let unit = marker.unit {
                            Text(unit).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(ProfilePalette.muted)
                        }
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                    LabStatusBadge(status: marker.status, copy: t, large: true).padding(.top, 8)
                }
            }

            LabBlockCard(title: t.why, text: marker.whyItMatters)
            LabBlockCard(title: t.explanation, text: marker.explanation)
            LabBlockCard(title: t.plan, text: marker.inYourPlan, tinted: true)

            if !history.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 0) {
                        LabKicker(t.earlier).padding(.bottom, 4)
                        ForEach(Array(history.enumerated()), id: \.offset) { index, earlier in
                            HStack(spacing: 10) {
                                Text(LabSampleDate.format(earlier.sampledAt, language: result.language))
                                    .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(earlier.unit.map { "\(earlier.value) \($0)" } ?? earlier.value)
                                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                LabStatusBadge(status: earlier.status, copy: t)
                            }
                            .frame(minHeight: 44)
                            .overlay(alignment: .top) { if index > 0 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            LabAskButton(copy: t).padding(.top, 6)
            LabFootnote(text: "\(t.validated). \(t.disclaimer)")
        }
    }
}
