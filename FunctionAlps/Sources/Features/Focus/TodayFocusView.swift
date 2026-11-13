import SwiftUI

/// Today's focus as a page (owner, 2026-11-13): where the member lands once they save the morning check-in. The cell's headline and
/// line, the practitioner line when it applies, the habit choices (choose one, "Do it now" or "Add to my morning routine"), and the
/// kickoff morning routine on a hard morning, all drawn by `TodayFocusCard`, the same card Home keeps under "My health plan".
struct TodayFocusView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                VStack(alignment: .leading, spacing: FASpacing.xs) {
                    Text(String(localized: "focus.page.title", defaultValue: "Morning check-in done"))
                        .font(FATypography.largeTitle).foregroundStyle(FAColor.ink)
                    Text(String(localized: "focus.page.subtitle", defaultValue: "Here is what your morning points to for today."))
                        .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, FASpacing.sm)
                TodayFocusCard()
                FAButton(title: String(localized: "focus.page.home", defaultValue: "Back to Home"), style: .tertiary) { router.pop() }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationTitle(String(localized: "focus.title", defaultValue: "Today's focus"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
