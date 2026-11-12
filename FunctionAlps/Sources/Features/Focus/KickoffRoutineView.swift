import SwiftUI

/// "Kickoff morning routine" — the routine for a slow or difficult morning, walked one step per screen: movement, breathing,
/// light, connection & positivity, hydration, a high-protein breakfast — in that order, each a real action card. Tick to go on,
/// then a finish screen. The routine (its order, its title, its words) is the server's (`member-daily-focus` → `cell.kickoff`);
/// the phone only walks it. Nothing here is written: it is a guided moment, not a plan entry.
struct KickoffRoutineView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var progress = KickoffProgress(total: 0)
    @State private var started = false
    /// The first read of the focus has finished (success or not): until then the screen is loading, never "not available".
    @State private var checked = false

    private var kickoff: FocusKickoff? { dependencies.focus.focus?.cell?.kickoff }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                backRow
                if let kickoff, kickoff.steps.count >= 2, started {
                    if progress.isFinished { finish(kickoff) } else { step(kickoff) }
                } else if !checked {
                    FALoadingState()
                } else {
                    FACard {
                        FAEmptyState(title: String(localized: "kickoff.missing.title", defaultValue: "This routine isn't available"),
                                     message: String(localized: "kickoff.missing.message", defaultValue: "Open Today's focus again from Home."),
                                     systemImage: "sunrise")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await begin() }
    }

    /// The first open: the focus may still be loading (a deep link), so wait for it; start on the first step.
    private func begin() async {
        guard !started else { return }
        await dependencies.focus.load()
        defer { checked = true }
        guard let kickoff, kickoff.steps.count >= 2 else { return }
        started = true
        progress = KickoffProgress(total: kickoff.steps.count)
        #if DEBUG
        // The showcase's finish screen: every step ticked.
        if Showcase.screen == .focusKickoffDone { for _ in kickoff.steps { progress.tick() } }
        #endif
    }

    private var backRow: some View {
        Button { dismiss() } label: {
            Text("‹ " + String(localized: "focus.title", defaultValue: "Today's focus"))
                .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                .faFrost(cornerRadius: 14, horizontal: 12, vertical: 8)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: A step

    @ViewBuilder
    private func step(_ kickoff: FocusKickoff) -> some View {
        let index = min(progress.stepNumber, kickoff.steps.count) - 1
        let current = kickoff.steps[index]
        let last = index == kickoff.steps.count - 1
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kickoff.title.uppercased())
                        .font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
                    Text(String(localized: "kickoff.stepOf", defaultValue: "Step \(progress.stepNumber) of \(progress.total)"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                dots(current: index, total: kickoff.steps.count)
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.label.uppercased())
                        .font(FATypography.sans(11, .bold, relativeTo: .caption)).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                    Text(current.title)
                        .font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = current.description, !detail.isEmpty {
                        Text(detail).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink2)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { router.push(.bankCard(current.cardId)) } label: {
                    Text(String(localized: "kickoff.seeCard", defaultValue: "See the full action"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.brand)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                FAButton(title: last ? String(localized: "kickoff.finish", defaultValue: "Done · finish")
                                     : String(localized: "kickoff.next", defaultValue: "Done · next step")) {
                    withAnimation(.easeOut(duration: 0.2)) { progress.tick() }
                }
                if progress.canGoBack {
                    FAButton(title: String(localized: "kickoff.back", defaultValue: "Previous step"), style: .tertiary) {
                        withAnimation(.easeOut(duration: 0.2)) { progress.back() }
                    }
                }
            }
        }
        .id("showcase.kickoff")
    }

    /// One dot per step: done · now · to come — by shape and fill, not colour alone (rule 10).
    private func dots(current: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? FAColor.brand : FAColor.forestMist)
                    .frame(width: i == current ? 26 : 12, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The end

    private func finish(_ kickoff: FocusKickoff) -> some View {
        FACard {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44)).foregroundStyle(FAColor.forestSoft)
                    .padding(.top, 8).accessibilityHidden(true)
                Text(kickoff.finishTitle ?? kickoff.title)
                    .font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = kickoff.finishLine {
                    Text(line).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FAButton(title: String(localized: "kickoff.home", defaultValue: "Back to Home")) {
                    router.tab = .home
                    router.homePath = []
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .id("showcase.kickoff")
    }
}
