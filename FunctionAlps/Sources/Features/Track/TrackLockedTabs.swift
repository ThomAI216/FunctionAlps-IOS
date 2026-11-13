import SwiftUI

/// Trends and Food on the Foundation Track (Thomas, 2026-11-06): locked until the member uses the app — Trends after
/// 3 days in a row (a check-in or a meal photo), Food with the first meal photo. The lock says how to open it and
/// offers the step that does. Off the track, or once open, the real tab shows (`UnlockService`, fail-open).
struct TrendsTabRoot: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        switch TrackLockGate.state(onTrack: dependencies.track.status?.state == .active,
                                   known: dependencies.unlocks.phase == .known, open: dependencies.unlocks.trendsOpen) {
        case .open: TrendsView()
        case .checking: FALoadingState().faWall()
        case .locked: TrendsLockedView(streak: dependencies.unlocks.streak)
        }
    }
}

struct FoodTabRoot: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        switch TrackLockGate.state(onTrack: dependencies.track.status?.state == .active,
                                   known: dependencies.unlocks.phase == .known, open: dependencies.unlocks.foodOpen) {
        case .open: FoodView()
        case .checking: FALoadingState().faWall()
        case .locked: FoodLockedView()
        }
    }
}

/// Which face a lockable tab shows. Pure.
enum TrackLockGate: Equatable {
    case open, checking, locked

    static func state(onTrack: Bool, known: Bool, open: Bool) -> TrackLockGate {
        guard onTrack else { return .open }
        guard known else { return .checking }
        return open ? .open : .locked
    }
}

private struct TrendsLockedView: View {
    @Environment(AppRouter.self) private var router
    let streak: Int

    var body: some View {
        let reached = min(streak, TrackUnlocks.trendsStreak)
        TrackLockCard(
            symbol: "chart.line.uptrend.xyaxis",
            title: String(localized: "lock.trends.title", defaultValue: "Your trends open after 3 days in a row"),
            message: String(localized: "lock.trends.message",
                            defaultValue: "Use the app three days in a row, with a check-in or a meal photo, and your curves appear here."),
            progress: (reached, TrackUnlocks.trendsStreak),
            button: String(localized: "lock.trends.button", defaultValue: "Do today's check-in")
        ) {
            if let url = URL(string: "functionalps://checkin/evening") { router.open(url) }
        }
    }
}

private struct FoodLockedView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var capture = MealCaptureCoordinator()

    var body: some View {
        TrackLockCard(
            symbol: "fork.knife",
            title: String(localized: "lock.food.title", defaultValue: "Food opens with your first meal photo"),
            message: String(localized: "lock.food.message",
                            defaultValue: "Photograph your next meal. From then on, Food shows what you eat, day after day."),
            progress: nil,
            button: String(localized: "lock.food.button", defaultValue: "Photograph a meal")
        ) {
            capture.openPhotoChooser()
        }
        .mealCaptureHost(capture) { Task { await dependencies.unlocks.refresh(force: true) } }
    }
}

/// The lock itself: what opens the tab, how far along, and the one step that helps.
private struct TrackLockCard: View {
    let symbol: String
    let title: String
    let message: String
    let progress: (done: Int, of: Int)?
    let button: String
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            FACard {
                VStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(FAColor.forest)
                            .frame(width: 64, height: 64)
                            .background(FAColor.forestSoft.opacity(0.16), in: Circle())
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(FAColor.forest, in: Circle())
                    }
                    .accessibilityHidden(true)
                    Text(title).font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if let progress {
                        HStack(spacing: 8) {
                            ForEach(0..<progress.of, id: \.self) { i in
                                Circle().fill(i < progress.done ? FAColor.forestSoft : FAColor.forestSoft.opacity(0.2))
                                    .frame(width: 14, height: 14)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "lock.progress", defaultValue: "\(progress.done) of \(progress.of) days"))
                        Text(String(localized: "lock.progress", defaultValue: "\(progress.done) of \(progress.of) days"))
                            .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestDark)
                            .accessibilityHidden(true)
                    }
                    ForestPillButton(title: button, action: action)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 0)
        }
        .padding(.bottom, FASpacing.navBarClearance / 2)
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}
