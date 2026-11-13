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
        case today, todayBottom = "today-bottom", profile, checkin, checkinMood = "checkin-mood", checkinDone = "checkin-done", meal, food, trends, scores, careplan, action, library, episode, symptoms, article, onboarding
        /// The practice's answer with resources, and the mini track they land on (2026-11-05).
        case messages, sentTrack = "sent-track", personalTrack = "personal-track"
        /// The action-card anatomy for the content brief: one complete card from the top, middle and bottom, a breathing card, the bank.
        case card, cardMiddle = "card-middle", cardBottom = "card-bottom", cardBreath = "card-breath", bank
        /// The Foundation Track, screen by screen, on real content (`ShowcaseTrack`): Home on a day, a questionnaire step,
        /// a track action's card, the day's read, the approved day-7 summary.
        case track, trackQuestionnaire = "track-q", trackCard = "track-card", trackRead = "track-read", trackSummary = "track-summary"
        /// The daily functional check-in rework (owner, 2026-11-10): the sleep dial, a wearable's night, the stool card,
        /// the red-flag card with the voice note, the Bristol chart open over the stool card.
        case checkinSleep = "checkin-sleep", checkinWearable = "checkin-wearable", checkinStool = "checkin-stool", checkinNote = "checkin-note", bristolChart = "bristol-chart"
        /// The dial with the moon held under the finger.
        case checkinSleepDrag = "checkin-sleep-drag"
        /// The moment after a validated meal ("Bon appétit"), over Home.
        case bonAppetit = "bon-appetit"
        /// "My health plan" scrolled to the goals and to the supplements (owner, 2026-11-10).
        case careplanMiddle = "careplan-middle", careplanBottom = "careplan-bottom"
        /// The Trends rework (owner-validated mockup v2, 2026-11-10): the page from its middle and its bottom, the Energy row
        /// opened in place, and the pages behind it — Sleep, Digestion, a device (Oura), the patterns the practitioner shared.
        case trendsMiddle = "trends-middle", trendsBottom = "trends-bottom", trendsEnergyOpen = "trends-energy-open"
        case trendsSleep = "trends-sleep", trendsDigestion = "trends-digestion", trendsDevice = "trends-device", trendsPatterns = "trends-patterns"
        /// The signal explanations (owner, 2026-11-11): "About energy" from its top and scrolled to the plate and the actions,
        /// "About sleep", "About digestion".
        case signalAboutEnergy = "signal-about-energy", signalAboutEnergyBottom = "signal-about-energy-bottom"
        case signalAboutSleep = "signal-about-sleep", signalAboutDigestion = "signal-about-digestion"
        /// The new Library (2026-11-10): the soft-lock sheet, search results, a read with Practice it, a video in the app's player.
        /// (`library` itself is its home.)
        case libraryLocked = "library-locked", librarySearch = "library-search", libraryRead = "library-read", libraryWatch = "library-watch"
        /// The habit screens (2026-11-10): the moment card, a row opened a little, a habit's page with a streak, a page on its first day.
        case habits, habitOpen = "habit-open", habitPage = "habit-page", habitFirst = "habit-first"
        /// The new MORNING check-in (owner-validated 2026-11-12): the top (sleep + "Feeling for the day"), the bottom (reveal row,
        /// done button, yesterday prompt), yesterday revealed, the two end screens, and a saved daily check-in showing the lock question.
        case morningTop = "morning-top", morningBottom = "morning-bottom", morningYesterday = "morning-yesterday"
        case morningEndGreen = "morning-end-green", morningEndLowEnergy = "morning-end-lowenergy", checkinLocked = "checkin-locked"
        /// Today's focus (owner-approved matrix, 2026-11-12): Home's card on P1 · P5 (with the practitioner line) · G1, the habit-choice
        /// sheet, an action opened from it (the two focus buttons), the kickoff morning routine (first step, finish) and the evening follow-up.
        case focusP1 = "focus-p1", focusP5 = "focus-p5", focusG1 = "focus-g1", focusSheet = "focus-sheet", focusAction = "focus-action"
        case focusKickoff = "focus-kickoff", focusKickoffDone = "focus-kickoff-done", focusEvening = "focus-evening"
        /// The page the morning check-in opens once saved (owner, 2026-11-13), on P1 and on P5.
        case focusPageP1 = "focus-page-p1", focusPageP5 = "focus-page-p5"
        /// Home's "During the day" list with the green "Kickoff morning routine" row (owner, 2026-11-13): not done, and done.
        case focusHome = "focus-home", focusHomeDone = "focus-home-done"
        /// The same row past its deadline (Missed), finished after it (Done late), and a Foundation Track member's Home with it.
        case focusHomeMissed = "focus-home-missed", focusHomeLate = "focus-home-late", focusTrackHome = "focus-track-home"
    }

    /// The screen asked for on the command line, nil in every normal launch.
    static let screen: Screen? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-FAShowcase"), i + 1 < args.count else { return nil }
        return Screen(rawValue: args[i + 1])
    }()

    static var isOn: Bool { screen != nil }

    /// The two "check-in in progress" shots (Energy & focus, then the whole Mood card): the same filled-in evening.
    static var isCheckinInProgress: Bool {
        switch screen {
        case .checkin, .checkinMood, .checkinSleep, .checkinSleepDrag, .checkinWearable, .checkinStool, .checkinNote, .bristolChart: true
        default: false
        }
    }

    /// The three morning check-in shots (a first morning, answers in progress).
    static var isMorningShot: Bool {
        switch screen {
        case .morningTop, .morningBottom, .morningYesterday: true
        default: false
        }
    }

    /// The old end-screen shots (`MorningEndView`, no longer shown after the check-in since 2026-11-13) draw it over the app (`FunctionAlpsApp`).
    static var morningEndRule: MorningRule? {
        switch screen {
        case .morningEndGreen: MorningRules.rule(mood: 82, energy: 74, motivation: 76)
        case .morningEndLowEnergy: MorningRules.rule(mood: 82, energy: 28, motivation: 76)
        default: nil
        }
    }

    /// The Trends screenshots: the sample member also has an Oura ring, 35 days of check-ins and two validated patterns.
    static var isTrends: Bool {
        switch screen {
        case .trends, .trendsMiddle, .trendsBottom, .trendsEnergyOpen, .trendsSleep, .trendsDigestion, .trendsDevice, .trendsPatterns,
             .signalAboutEnergy, .signalAboutEnergyBottom, .signalAboutSleep, .signalAboutDigestion: true
        default: false
        }
    }

    /// The daily check-in shots whose digestion is filled in (the stool card, the note, the chart).
    static var isDigestionShot: Bool { screen == .checkinStool || screen == .checkinNote || screen == .bristolChart }

    /// Scrolls a screen to the part the screenshot frames (there is no finger in the simulator): only for `on`.
    @MainActor
    static func scroll(_ proxy: ScrollViewProxy, to id: String, on target: Screen, anchor: UnitPoint = .top) async {
        guard screen == target else { return }
        try? await Task.sleep(for: .seconds(1.5))
        proxy.scrollTo(id, anchor: anchor)
    }

    /// Where the app opens — the same `functionalps://` links notifications use.
    static var route: URL? {
        guard let screen else { return nil }
        let link: String = switch screen {
        case .today, .todayBottom, .checkinDone, .onboarding, .track, .trackQuestionnaire, .bonAppetit, .habits, .habitOpen,
             .morningEndGreen, .morningEndLowEnergy, .focusHome, .focusHomeDone, .focusHomeMissed, .focusHomeLate, .focusTrackHome: "functionalps://home"
        case .focusAction: "functionalps://focus/card/\(ShowcaseFocus.actionCardId)"
        case .focusKickoff, .focusKickoffDone: "functionalps://focus/kickoff"
        // Today's focus lives on its own page now (Home no longer carries the card): the page, and the habit-choice sheet over it.
        case .focusPageP1, .focusPageP5, .focusP1, .focusP5, .focusG1, .focusSheet: "functionalps://focus/today"
        case .focusEvening: "functionalps://checkin/evening"
        case .morningTop, .morningBottom, .morningYesterday: "functionalps://checkin/morning"
        case .checkinLocked: "functionalps://checkin/evening"
        case .habitPage, .habitFirst: "functionalps://habit/\(ShowcaseHabits.pageKey)"
        case .trackCard: "functionalps://foundation/card/\(ShowcaseTrack.cardId)/\(ShowcaseTrack.face)"
        case .trackRead: "functionalps://foundation/read/\(ShowcaseTrack.slug)"
        case .trackSummary: "functionalps://foundation/summary"
        case .profile: "functionalps://profile"
        case .checkin, .checkinMood, .checkinSleep, .checkinSleepDrag, .checkinWearable, .checkinStool, .checkinNote, .bristolChart: "functionalps://checkin/evening"
        case .meal: "functionalps://meal/\(ShowcaseData.heroMealId)"
        case .food: "functionalps://food"
        case .trends, .trendsMiddle, .trendsBottom, .trendsEnergyOpen: "functionalps://trends"
        case .trendsSleep: "functionalps://trends/signal/sleep"
        case .trendsDigestion: "functionalps://trends/signal/digestion"
        case .trendsDevice: "functionalps://trends/device/\(ShowcaseData.trendsDeviceKey)"
        case .trendsPatterns: "functionalps://trends/patterns"
        case .signalAboutEnergy, .signalAboutEnergyBottom: "functionalps://trends/about/energy"
        case .signalAboutSleep: "functionalps://trends/about/sleep"
        case .signalAboutDigestion: "functionalps://trends/about/digestion"
        case .scores: "functionalps://scores"
        case .careplan, .careplanMiddle, .careplanBottom: "functionalps://careplan"
        case .action: "functionalps://action/\(ShowcaseData.actionHabitId)"
        case .card, .cardMiddle, .cardBottom: "functionalps://action/\(ShowcaseData.anatomyHabitId)"
        case .cardBreath: "functionalps://bank/\(ShowcaseData.breathCardId)"
        case .bank: "functionalps://bank"
        case .library, .libraryLocked, .librarySearch: "functionalps://library"
        case .libraryRead: "functionalps://library/\(ShowcaseLibrary.readSlug)"
        case .libraryWatch: "functionalps://library/watch"
        case .messages: "functionalps://messages"
        case .sentTrack: "functionalps://library/sent"
        case .personalTrack: "functionalps://library/track/\(ShowcaseData.personalTrackId)"
        case .episode: "functionalps://library/show/\(ShowcaseData.showEpisodeSlug)"
        case .symptoms: "functionalps://checkin/gut"
        case .article: "functionalps://library/\(ShowcaseData.articleSlug)"
        }
        return URL(string: link)
    }
}
#endif
