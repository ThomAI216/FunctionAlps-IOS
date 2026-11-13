import SwiftUI

/// Shown on the plan screen when the member has no published plan but a DRAFT exists: they know a plan is coming,
/// they cannot read it. The stand-in is generic (bars, no words from the draft) and hidden from VoiceOver; the
/// card above it says what is happening.
struct DraftPlanPreparingView: View {
    var body: some View {
        VStack(spacing: 14) {
            FACard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hourglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.forest)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "plan.draft.title", defaultValue: "Your plan is being prepared"))
                            .font(FATypography.headline).foregroundStyle(FAColor.ink)
                        Text(String(localized: "plan.draft.message", defaultValue: "Your care team is finishing your plan. We'll let you know as soon as it's ready."))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            FACard {
                VStack(alignment: .leading, spacing: 18) {
                    PlanPlaceholderLines(lines: 3)
                    PlanPlaceholderLines(lines: 4)
                    PlanPlaceholderLines(lines: 1, chips: true)
                }
                .blur(radius: 7)
                .opacity(0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
