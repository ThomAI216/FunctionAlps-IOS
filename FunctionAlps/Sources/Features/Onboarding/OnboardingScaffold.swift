import SwiftUI

/// The frame every onboarding screen sits in (the Expo `OnboardingScaffold`): step bar, scrolling body,
/// pinned CTA. The point is consistency of RHYTHM — eyebrow, one large serif title, a short paragraph,
/// then cards — so the flow reads as one thing rather than eight pages (PRD §20).
struct OnboardingScaffold<Content: View>: View {
    let step: OnboardingStep
    let eyebrow: String
    let title: Text
    var onBack: (() -> Void)? = nil
    let primary: String
    var primaryEnabled = true
    var primaryBusy = false
    let onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: () -> Void = {}
    /// Small line under the CTA — errors, retries, "you can change this later".
    var footnote: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).foregroundStyle(ProfilePalette.muted)
                            .frame(width: 36, height: 36, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
                StepBar(step: step)
            }
            .padding(.horizontal, 22).padding(.top, 4)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(eyebrow.uppercased())
                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.forestSoft)
                        .padding(.bottom, 10)
                        .accessibilityAddTraits(.isHeader)
                    title
                        .font(FATypography.display(30, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).lineSpacing(5)
                        .padding(.bottom, 14)
                    content
                }
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 0) {
                ForestPillButton(title: primary, enabled: primaryEnabled, busy: primaryBusy, action: onPrimary)
                if let secondary {
                    Button(action: onSecondary) {
                        Text(secondary).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let footnote { footnote.padding(.top, 10) }
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
            .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Eight segments, one per screen; the ones reached are forest.
struct StepBar: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...OnboardingStep.total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i <= step.rawValue ? FAColor.forestSoft : ProfilePalette.surfaceSoft)
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "ob.step.a11y", defaultValue: "Step \(step.rawValue) of \(OnboardingStep.total)"))
    }
}

/// Body copy at the onboarding's reading size.
struct OBParagraph: View {
    let text: String
    var strong = false
    init(_ text: String, strong: Bool = false) { self.text = text; self.strong = strong }

    var body: some View {
        Text(text)
            .font(FATypography.sans(15, strong ? .semibold : .regular, relativeTo: .body))
            .foregroundStyle(strong ? FAColor.ink : ProfilePalette.muted)
            .lineSpacing(7)
    }
}

/// A glass card with a leading icon tile, a title and a line — the welcome / ready cards.
struct OBIconCard: View {
    let symbol: String
    let title: String
    let line: String

    var body: some View {
        FACard(padded: false) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProfilePalette.accentSoft)
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(FATypography.sans(14.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    Text(line).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                }
            }
            .padding(15)
        }
    }
}

/// The small rounded pill used for the nutrient / capture / symptom lists.
struct OBChip: View {
    let label: String
    var dot: Color? = nil
    var muted = false

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(label).font(FATypography.sans(muted ? 12 : 12.5, muted ? .regular : .medium, relativeTo: .caption)).foregroundStyle(muted ? ProfilePalette.muted : FAColor.ink)
        }
        .padding(.horizontal, muted ? 10 : 11).padding(.vertical, muted ? 5 : 6)
        .background(muted ? ProfilePalette.surface : ProfilePalette.surfaceSoft, in: Capsule())
        .overlay { Capsule().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
    }
}
