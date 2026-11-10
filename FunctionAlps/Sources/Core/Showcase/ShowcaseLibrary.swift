#if DEBUG
import Foundation

/// The new Library as the showcase screenshots show it (Thomas, 2026-11-10): the sample member "Marie" on day 10 of the
/// Foundation Track, the 29 reads as the library lists them (`ShowcaseLibraryContent`, real practice content), the habits of
/// the new plan with their reads and videos. Everything is answered from here: no network, no real member.
///
/// Scenes (`-FAShowcase <id>`): `library` (home) · `library-locked` (the "Opens on day 11" sheet) · `library-search`
/// (results for `-FAQuery`, default "sleep") · `library-read` (a read, with Practice it) · `library-watch` (a YouTube video, in
/// the app's player). Optional: `-FATrackDay <n>` moves the member's day.
enum ShowcaseLibrary {
    static var isOn: Bool {
        switch Showcase.screen {
        case .library?, .libraryLocked?, .librarySearch?, .libraryRead?, .libraryWatch?: true
        default: false
        }
    }

    static let readSlug = "light-sets-your-body-clock"
    static var query: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-FAQuery"), i + 1 < args.count else { return "sleep" }
        return args[i + 1]
    }

    // MARK: The list

    private static func tags(_ a: (day: Int, slug: String, title: String, summary: String, minutes: Int, pillar: String)) -> [String] {
        ["article", "foundation-track", "minutes:\(a.minutes)", "day:\(a.day)"] + (a.pillar.isEmpty ? [] : [a.pillar])
    }

    static func raw() -> LibraryRaw {
        var raw = LibraryRaw()
        raw.list = ShowcaseLibraryContent.articles.map {
            LibraryListRow(slug: $0.slug, title: $0.title, summary: $0.summary, publishedAt: nil, tags: tags($0), isLocked: false, coverUrl: nil)
        }
        // Marie has read the days behind her, except one read of day 4 (so the day reads "2 of 3" and the reader can be marked).
        let day = ShowcaseTrack.day
        raw.progress = ShowcaseLibraryContent.articles.filter { $0.day < day && $0.slug != readSlug }
            .map { LibraryRawProgress(trackId: nil, contentSlug: $0.slug) }
        raw.access = .open
        return raw
    }

    static var readSlugs: Set<String> { Set(raw().progress.map(\.contentSlug)) }

    static func item(slug: String) -> LibraryGetRow? {
        guard let a = ShowcaseLibraryContent.articles.first(where: { $0.slug == slug }) else { return nil }
        return LibraryGetRow(title: a.title, tags: tags(a), bodyMd: ShowcaseLibraryContent.body(slug: slug) ?? LibraryDemo.readerBody, locked: false, summary: a.summary)
    }

    // MARK: The plan's habits (cards, with their reads and videos) and the track's days

    private static let cardsJSON = ##"""
    [
     {"id":"lib-daylight","pillar":"sleep","card_kind":"routine","duration_min":5,"title":"Daylight first thing","default_slot":"morning","member_can_add":true,
      "resources":[{"kind":"article","slug":"light-sets-your-body-clock","title":"Light sets your body clock"}]},
     {"id":"lib-caffeine","pillar":"sleep","card_kind":"nutrition","title":"No caffeine after 16:00","default_slot":"midday","member_can_add":true,
      "resources":[{"kind":"article","slug":"caffeine-and-your-sleep","title":"Caffeine and your sleep"}]},
     {"id":"lib-breathing","pillar":"mind","card_kind":"breath","duration_min":5,"title":"5 minutes of breathing","default_slot":"midday","member_can_add":true,
      "resources":[{"kind":"article","slug":"breathe-the-time-you-give-yourself","title":"Breathe: the time you give yourself"},
                   {"kind":"video","url":"https://www.youtube.com/watch?v=nzCaZQqAs9I","title":"Guided breathing, with Wim Hof","source":"youtube"}]},
     {"id":"lib-flow","pillar":"exercise","card_kind":"movement","duration_min":5,"title":"The 5-minute morning flow","default_slot":"morning","member_can_add":true,
      "resources":[{"kind":"video","url":"https://media.functionalps.ch/videos/morning-flow.mp4","title":"The 5-minute morning flow","source":"own"}]},
     {"id":"lib-321","pillar":"sleep","card_kind":"routine","title":"The 3-2-1 rule","default_slot":"evening","member_can_add":true,
      "resources":[{"kind":"article","slug":"the-3-2-1-rule","title":"The 3-2-1 rule"}]},
     {"id":"lib-book","pillar":"sleep","card_kind":"routine","title":"A book instead of a screen","default_slot":"evening","member_can_add":true,
      "resources":[{"kind":"article","slug":"your-evening-routine","title":"Your evening routine"}]},
     {"id":"lib-winddown","pillar":"sleep","card_kind":"breath","duration_min":10,"title":"10 minutes to wind down","default_slot":"evening","member_can_add":true,
      "resources":[{"kind":"article","slug":"nsdr-explained","title":"NSDR, explained"},
                   {"kind":"video","url":"https://www.youtube.com/watch?v=KHIbgSN2qAU","title":"10-minute NSDR","source":"youtube"}]},
     {"id":"lib-nodevices","pillar":"sleep","card_kind":"routine","title":"No screens in your last hour","default_slot":"evening","member_can_add":true,
      "resources":[{"kind":"article","slug":"light-sets-your-body-clock","title":"Light sets your body clock"}]}
    ]
    """##

    static let cards: [ActionCardRow] = (try? JSON.decoder.decode([ActionCardRow].self, from: Data(cardsJSON.utf8))) ?? []

    /// (first day, key, moment, card, reads) — an action runs from its first day on.
    private static let actions: [(from: Int, key: String, moment: TrackMoment, card: String, reads: [String])] = [
        (4, "daylight", .morning, "lib-daylight", ["light-sets-your-body-clock"]),
        (4, "caffeine", .midday, "lib-caffeine", ["caffeine-and-your-sleep"]),
        (5, "breathing", .midday, "lib-breathing", ["breathe-the-time-you-give-yourself"]),
        (7, "flow_5", .morning, "lib-flow", []),
        (4, "rule_321", .evening, "lib-321", ["the-3-2-1-rule"]),
        (10, "book", .evening, "lib-book", ["your-evening-routine"]),
        (10, "wind_down", .evening, "lib-winddown", ["nsdr-explained"]),
    ]

    private static let dayTitles: [Int: String] = [
        1: "Your starting point", 2: "Nutrition", 3: "Movement", 4: "Sleep", 5: "Mental and emotional health", 6: "Your first week",
        7: "Your full day", 8: "Protein first", 9: "A lunch that holds you", 10: "Your evening in three", 11: "Your mind, day to day",
        12: "More morning movement", 13: "Make it yours", 14: "Your two weeks",
    ]

    /// The primary read of a day (the one the track card opens).
    private static let primary: [Int: String] = [4: "light-sets-your-body-clock", 10: "your-evening-routine"]

    static let days: [TrackDay] = (1...14).map { n in
        var day = TrackDay(day: n, titleEn: dayTitles[n] ?? "Day \(n)")
        day.readSlug = primary[n]
        day.actions = actions.filter { $0.from <= n }.map { a in
            var action = TrackAction(key: a.key, moment: a.moment)
            action.habitBankId = a.card
            action.reads = a.reads
            return action
        }
        return day
    }

    // MARK: The video of the "library-watch" scene

    static var video: LibraryVideo {
        LibraryVideo(url: URL(string: "https://www.youtube.com/watch?v=nzCaZQqAs9I")!, title: "Guided breathing, with Wim Hof", cardId: "lib-breathing")
    }
}
#endif
