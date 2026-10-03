#if DEBUG
import SwiftUI

/// The members-showcase screenshots (owner, 2026-10-02): the app, signed in as a SAMPLE member ("Marie", three
/// weeks of check-ins and meals, an energy / focus / sleep plan), opened straight on one screen. Debug builds only — the
/// whole folder is compiled out of Release, so TestFlight and the App Store never contain it — and it reads no
/// network data: `ShowcaseBackend` answers every call from the samples below. Nothing here is a real person.
///
/// Launched by the `Screenshots` workflow: `-FAShowcase <screen>` (see `Screen`).
enum Showcase {
    enum Screen: String, CaseIterable {
        case today, checkin, checkinMood = "checkin-mood", checkinDone = "checkin-done", meal, food, trends, scores, careplan, action, library, episode, symptoms, article, onboarding
    }

    /// The screen asked for on the command line, nil in every normal launch.
    static let screen: Screen? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-FAShowcase"), i + 1 < args.count else { return nil }
        return Screen(rawValue: args[i + 1])
    }()

    static var isOn: Bool { screen != nil }

    /// The two "check-in in progress" shots (Energy & focus, then the whole Mood card): the same filled-in evening.
    static var isCheckinInProgress: Bool { screen == .checkin || screen == .checkinMood }

    /// Scrolls a screen to the part the screenshot frames (there is no finger in the simulator): only for `on`.
    @MainActor
    static func scroll(_ proxy: ScrollViewProxy, to id: String, on target: Screen) async {
        guard screen == target else { return }
        try? await Task.sleep(for: .seconds(1.5))
        proxy.scrollTo(id, anchor: .top)
    }

    /// Where the app opens — the same `functionalps://` links notifications use.
    static var route: URL? {
        guard let screen else { return nil }
        let link: String = switch screen {
        case .today, .checkinDone, .onboarding: "functionalps://home"
        case .checkin, .checkinMood: "functionalps://checkin/evening"
        case .meal: "functionalps://meal/\(ShowcaseData.heroMealId)"
        case .food: "functionalps://food"
        case .trends: "functionalps://trends"
        case .scores: "functionalps://scores"
        case .careplan: "functionalps://careplan"
        case .action: "functionalps://action/\(ShowcaseData.actionHabitId)"
        case .library: "functionalps://library"
        case .episode: "functionalps://library/show/\(ShowcaseData.showEpisodeSlug)"
        case .symptoms: "functionalps://checkin/gut"
        case .article: "functionalps://library/\(ShowcaseData.articleSlug)"
        }
        return URL(string: link)
    }
}
#endif
