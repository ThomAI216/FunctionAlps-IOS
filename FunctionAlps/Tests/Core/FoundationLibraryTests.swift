import Foundation
import Testing
@testable import FunctionAlps

@Suite("Library home — the Foundation Track by day, search, the reads for your habits, Practice it")
struct FoundationLibraryTests {
    // MARK: Fixtures

    private func article(_ slug: String, day: Int? = nil, minutes: Int = 3, pillar: String? = nil, title: String? = nil, summary: String = "", extra: [String] = [], track: Bool = true) -> LibraryArticle {
        var tags = ["article"] + extra
        if track { tags.append("foundation-track") }
        if let day { tags.append("day:\(day)") }
        tags.append("minutes:\(minutes)")
        if let pillar { tags.append(pillar) }
        return LibraryArticle(slug: slug, title: title ?? LibraryLogic.title(fromSlug: slug), summary: summary, tags: tags)
    }

    private var library: [LibraryArticle] {
        [
            article("intro", day: 1, title: "Introduction to functional health"),
            article("mindful", day: 2, pillar: "nutrition", title: "Mindful eating"),
            article("light", day: 4, pillar: "sommeil", title: "Light sets your body clock", summary: "Daylight first thing in the morning tells your body clock the day has started."),
            article("caffeine", day: 4, pillar: "sommeil", title: "Caffeine and your sleep"),
            article("rule321", day: 4, pillar: "sommeil", title: "The 3-2-1 rule"),
            article("nsdr", day: 10, pillar: "sommeil", title: "NSDR, explained"),
            article("evening", day: 10, pillar: "sommeil", title: "Your evening routine"),
            article("connection", day: 11, pillar: "stress", title: "Connection is health"),
            article("magnesium", title: "Magnesium: which one, and when", extra: ["supplement"], track: false),
        ]
    }

    private func card(_ id: String, title: String, articles: [String] = [], videos: [String] = [], canAdd: Bool = true, slot: String? = nil) -> ActionCardRow {
        var c = ActionCardRow(id: id, title: title)
        c.memberCanAdd = canAdd
        c.defaultSlot = slot
        c.resources = articles.map { .init(kind: "article", slug: $0) } + videos.map { .init(kind: "video", url: $0, title: "Video of \(title)") }
        return c
    }

    private func habit(_ id: String, title: String, card: String?, status: String = "active") -> HabitRow {
        HabitRow(id: id, carePlanItemId: nil, title: title, description: nil, frequencyRule: "FREQ=DAILY", status: status, source: "self_initiated",
                 pillar: nil, slot: "evening", appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil, revTitle: nil, revDescription: nil,
                 createdAt: "2026-10-01T08:00:00+00:00", habitBankId: card)
    }

    // MARK: Tags

    @Test func theTagsSayTheDayTheReadingTimeAndTheTopic() {
        let a = article("light", day: 4, minutes: 4, pillar: "sommeil")
        #expect(a.day == 4 && a.minutes == 4 && a.isFoundationTrack)
        #expect(a.topicKey == "sommeil" && a.topic == LibraryLogic.topicName("sommeil"))
        let plain = LibraryArticle(slug: "x", title: "X", tags: ["article", "supplement"])
        #expect(plain.day == nil && plain.minutes == nil && !plain.isFoundationTrack && plain.topic == nil)
        // The `pillar:` form and the English name both reach the same topic.
        #expect(LibraryArticle(slug: "y", title: "Y", tags: ["pillar:sommeil"]).topicKey == "sommeil")
        #expect(LibraryArticle(slug: "z", title: "Z", tags: ["sleep"]).topicKey == "sommeil")
        #expect(LibraryArticle(slug: "w", title: "W", tags: ["day:abc", "day:0"]).day == nil)
    }

    @Test func theFourPillarsMapToTheirTopicWords() {
        #expect(LibraryLogic.topicName("sommeil") != nil)
        #expect(LibraryLogic.topicName("sleep") == LibraryLogic.topicName("sommeil"))
        #expect(Set(["sommeil", "nutrition", "mouvement", "stress"].compactMap(LibraryLogic.topicName)).count == 4)
        #expect(LibraryLogic.topicName("foundations") == nil)
    }

    // MARK: The member's day and the days

    private func status(day: Int, state: TrackStatus.State = .active) -> TrackStatus {
        var s = TrackStatus(state: state)
        s.day = day
        return s
    }

    @Test func theMembersDayIsOnlyKnownWhileOnTheTrack() {
        #expect(FoundationLibraryLogic.currentDay(status(day: 4)) == 4)
        #expect(FoundationLibraryLogic.currentDay(status(day: 14)) == 14)
        #expect(FoundationLibraryLogic.currentDay(status(day: 15)) == nil)     // the two weeks are over: everything opens
        #expect(FoundationLibraryLogic.currentDay(status(day: 3, state: .invited)) == nil)
        #expect(FoundationLibraryLogic.currentDay(nil) == nil)
    }

    @Test func daysGroupTheirReadsAndLeaveOutWhatIsNotOnTheTrack() {
        let groups = FoundationLibraryLogic.dayGroups(articles: library, today: 4, readSlugs: [])
        #expect(groups.map(\.day) == [1, 2, 4, 10, 11])
        #expect(groups.first { $0.day == 4 }?.reads.map(\.slug) == ["caffeine", "light", "rule321"])   // by title
        #expect(!groups.flatMap(\.reads).contains { $0.slug == "magnesium" })
    }

    @Test func theDaysOwnReadComesFirst() {
        let groups = FoundationLibraryLogic.dayGroups(articles: library, today: 4, readSlugs: [], primary: [4: "rule321"])
        #expect(groups.first { $0.day == 4 }?.reads.first?.slug == "rule321")
    }

    @Test func pastDaysReadTodayHighlightedDaysToComeSoftLocked() {
        let read: Set<String> = ["intro", "mindful"]
        let groups = FoundationLibraryLogic.dayGroups(articles: library, today: 4, readSlugs: read)
        #expect(groups.first { $0.day == 1 }?.status == .read)
        #expect(groups.first { $0.day == 2 }?.status == .read)
        #expect(groups.first { $0.day == 4 }?.phase == .today && groups.first { $0.day == 4 }?.status == .new)
        #expect(groups.first { $0.day == 10 }?.status == .locked(opensOnDay: 10))
        #expect(groups.first { $0.day == 11 }?.isOpenable == false)
        #expect(groups.first { $0.day == 1 }?.isOpenable == true)
        // A past day that was not read says so; a day with some reads says how many.
        let later = FoundationLibraryLogic.dayGroups(articles: library, today: 10, readSlugs: ["light"])
        #expect(later.first { $0.day == 1 }?.status == .unread)
        #expect(later.first { $0.day == 4 }?.status == .partial(done: 1, total: 3))
        #expect(later.first { $0.day == 10 }?.status == .new)
        #expect(later.first { $0.day == 11 }?.status == .locked(opensOnDay: 11))
    }

    @Test func aMemberOffTheTrackHasEveryDayOpen() {
        let groups = FoundationLibraryLogic.dayGroups(articles: library, today: nil, readSlugs: ["intro"])
        #expect(groups.allSatisfy { $0.isOpenable && $0.phase == .open })
        #expect(groups.first { $0.day == 1 }?.status == .read)
        #expect(groups.first { $0.day == 11 }?.status == .unread)
        let totals = FoundationLibraryLogic.readTotals(groups)
        #expect(totals.read == 1 && totals.total == 8)
    }

    @Test func aReadOfADayToComeNeverOpensBeforeItsDay() {
        let connection = library.first { $0.slug == "connection" }!
        #expect(FoundationLibraryLogic.opensOn(connection, today: 10) == 11)
        #expect(FoundationLibraryLogic.opensOn(connection, today: 11) == nil)
        #expect(FoundationLibraryLogic.opensOn(connection, today: nil) == nil)
        // Only Foundation Track reads wait; the rest of the library is always open.
        let magnesium = library.first { $0.slug == "magnesium" }!
        #expect(FoundationLibraryLogic.opensOn(magnesium, today: 1) == nil)
    }

    @Test func readNextIsTheOtherReadsOfTheDayThenTheNextDay_neverOneNotOpenYet() {
        let light = library.first { $0.slug == "light" }!
        // Day 4's other two reads, the unread one first.
        let next = FoundationLibraryLogic.readNext(after: light, articles: library, today: 4, readSlugs: ["caffeine"])
        #expect(next.map(\.slug) == ["rule321", "caffeine"])
        // The last read of a day goes on to the next day's, when it is open.
        let nsdr = library.first { $0.slug == "nsdr" }!
        #expect(FoundationLibraryLogic.readNext(after: nsdr, articles: library, today: 10, readSlugs: ["evening"], limit: 3).map(\.slug) == ["evening"])   // day 11 is not open on day 10
        #expect(FoundationLibraryLogic.readNext(after: nsdr, articles: library, today: 11, readSlugs: [], limit: 3).map(\.slug) == ["evening", "connection"])
        let magnesium = library.first { $0.slug == "magnesium" }!
        #expect(FoundationLibraryLogic.readNext(after: magnesium, articles: library, today: 4, readSlugs: []).isEmpty)
    }

    // MARK: Search

    private func search(_ query: String, habits: [LibraryHabit] = [], videos: [LibraryVideo] = []) -> LibrarySearch.Results {
        LibrarySearch.results(query: query, articles: library, habits: habits, videos: videos)
    }

    @Test func aTopicWordFindsTheTopicAndItsArticles() {
        let r = search("sleep")
        #expect(r.topics.map(\.key) == ["sommeil"])
        #expect(Set(r.articles.map(\.slug)) == ["light", "caffeine", "rule321", "nsdr", "evening"])
        // The pillar's own key and an accent-free spelling reach it too.
        #expect(search("sommeil").topics.map(\.key) == ["sommeil"])
        #expect(!search("mind").topics.isEmpty && search("mind").articles.map(\.slug).contains("connection"))
    }

    @Test func aTitleWordOutranksASummaryWord_andTheEarlierDayWinsATie() {
        let r = search("light")
        #expect(r.articles.first?.slug == "light")   // in the title
        let tie = search("sleep")
        #expect(tie.articles.map(\.day).compactMap { $0 } == tie.articles.map(\.day).compactMap { $0 }.sorted())
        // Summary words are found, ranked below the title.
        #expect(search("daylight").articles.map(\.slug) == ["light"])
    }

    @Test func everyWordOfTheQueryMustBeFound() {
        #expect(search("sleep caffeine").articles.map(\.slug) == ["caffeine"])
        #expect(search("caffeine zebra").isEmpty)
        #expect(search("   ").isEmpty)
        #expect(search("MAGNESIUM").articles.map(\.slug) == ["magnesium"])   // case and accents do not matter; supplements are still found
        #expect(search("énergie").topics.isEmpty)
    }

    @Test func searchAlsoFindsTheMembersHabitsAndTheVideos() {
        let habits = [LibraryHabit(title: "10 minutes to wind down", moment: .evening, target: .habit("h1")),
                      LibraryHabit(title: "Daylight first thing", moment: .morning, target: .trackCard("c1", face: "standard"))]
        let videos = [LibraryVideo(url: URL(string: "https://www.youtube.com/watch?v=tybOi4hjZFQ")!, title: "Guided breathing, with Wim Hof"),
                      LibraryVideo(url: URL(string: "https://www.youtube.com/watch?v=aaaaaaaaaaa")!, title: "10-minute NSDR")]
        #expect(search("wind", habits: habits, videos: videos).habits.map(\.title) == ["10 minutes to wind down"])
        #expect(search("daylight", habits: habits, videos: videos).habits.count == 1)
        #expect(search("breathing", habits: habits, videos: videos).videos.map(\.title) == ["Guided breathing, with Wim Hof"])
        #expect(search("nsdr", habits: habits, videos: videos).videos.count == 1 && search("nsdr", habits: habits, videos: videos).articles.map(\.slug) == ["nsdr"])
    }

    // MARK: For your habits

    @Test func forYourHabitsListsTheReadsOfTodaysActionsOnceEach_openOnesOnly() {
        let sources = [
            FoundationLibraryLogic.HabitReadSource(habitTitle: "Daylight first thing", slugs: ["light"]),
            FoundationLibraryLogic.HabitReadSource(habitTitle: "The 3-2-1 rule", slugs: ["rule321", "light", "nope"]),
            FoundationLibraryLogic.HabitReadSource(habitTitle: "Connect", slugs: ["connection"]),
        ]
        let reads = FoundationLibraryLogic.forYourHabits(sources: sources, articles: library, today: 10)
        #expect(reads.map(\.article.slug) == ["light", "rule321"])          // once each; unknown and not-yet-open ones left out
        #expect(reads.map(\.habitTitle) == ["Daylight first thing", "The 3-2-1 rule"])
        #expect(FoundationLibraryLogic.forYourHabits(sources: sources, articles: library, today: 11).map(\.article.slug) == ["light", "rule321", "connection"])
        #expect(FoundationLibraryLogic.forYourHabits(sources: [], articles: library, today: 10).isEmpty)
    }

    @Test func aTrackActionCarriesItsReads() throws {
        let day = Data(#"[{"day":4,"title_en":"Sleep","actions":[{"key":"daylight","moment":"morning","habit_bank_id":"c1","reads":["light-sets-your-body-clock"," the-3-2-1-rule ",""]},{"key":"x","moment":"evening"}]}]"#.utf8)
        let actions = try TrackJSON.decode([TrackDayWire].self, from: day)[0].day.actions
        #expect(actions[0].reads == ["light-sets-your-body-clock", "the-3-2-1-rule"])
        #expect(actions[1].reads.isEmpty)
    }

    // MARK: Practice it

    @Test func aHabitInTheActionsOpens_oneNotYetInThemGetsAnAdd() {
        let daylight = card("c-daylight", title: "Daylight first thing", articles: ["light"], slot: "morning")
        let screens = card("c-screens", title: "No screens in your last hour", articles: ["light"], slot: "evening")
        let other = card("c-other", title: "Something else", articles: ["rule321"])
        let cards = FoundationLibraryLogic.cards(linkingArticle: "light", in: [daylight, screens, other])
        #expect(cards.map(\.id) == ["c-daylight", "c-screens"])

        // On the track: the day's action opens its card; the other can be added.
        let items = FoundationLibraryLogic.practiceItems(cards: cards, plan: nil, trackActions: [.init(cardId: "c-daylight", face: "easy")], locale: "en")
        #expect(items.map(\.cardId) == ["c-daylight", "c-screens"])
        #expect(items[0].action == .open(.trackCard("c-daylight", face: "easy")) && items[0].moment == .morning)
        #expect(items[1].action == .add)

        // A habit of the member's own opens its habit; a habit they have is never offered twice.
        let plan = HabitPlan(day: "2026-11-10", header: nil, phases: [], habits: [habit("h-screens", title: "My screens rule", card: "c-screens")], completions: [])
        let mine = FoundationLibraryLogic.practiceItems(cards: cards, plan: plan, trackActions: [], locale: "en")
        #expect(mine.first { $0.cardId == "c-screens" }?.action == .open(.habit("h-screens")))
        #expect(mine.first { $0.cardId == "c-screens" }?.title == "My screens rule")
        #expect(mine.first { $0.cardId == "c-daylight" }?.action == .add)
        #expect(mine.map(\.cardId) == ["c-screens", "c-daylight"])   // what is already in the actions comes first
    }

    @Test func aCardTheMemberMayNotAddAndDoesNotHaveIsNotShown() {
        let locked = card("c-locked", title: "Prescribed only", articles: ["light"], canAdd: false)
        #expect(FoundationLibraryLogic.practiceItems(cards: [locked], plan: nil, trackActions: [], locale: "en").isEmpty)
        // …but once it is in their actions it opens.
        let items = FoundationLibraryLogic.practiceItems(cards: [locked], plan: nil, trackActions: [.init(cardId: "c-locked", face: "standard")], locale: "en")
        #expect(items.first?.action == .open(.trackCard("c-locked", face: "standard")))
        // A cancelled habit does not count as being in the actions.
        let cancelled = HabitPlan(day: "2026-11-10", header: nil, phases: [], habits: [habit("h", title: "Old", card: "c-locked", status: "cancelled")], completions: [])
        #expect(FoundationLibraryLogic.practiceItems(cards: [locked], plan: cancelled, trackActions: [], locale: "en").isEmpty)
    }

    // MARK: Watch

    @Test func videosAreCollectedOnceEachFromTheHabitsSoFar() {
        let breathing = card("b", title: "5 minutes of breathing", videos: ["https://www.youtube.com/watch?v=tybOi4hjZFQ", "https://media.functionalps.ch/flow.mp4"])
        let again = card("b2", title: "Breathing again", videos: ["https://www.youtube.com/watch?v=tybOi4hjZFQ"])
        let search = card("s", title: "Search card", videos: ["https://www.youtube.com/results?search_query=breathing"])
        let sources = [breathing, again, search].map { FoundationLibraryLogic.VideoSource(cardId: $0.id, cardTitle: $0.title, links: ActionCardLogic.links($0.resources)) }
        let videos = FoundationLibraryLogic.videos(from: sources)
        #expect(videos.count == 2)            // the repeat and the YouTube search page (not a video) are left out
        #expect(videos[0].isYouTube && videos[0].youtubeID == "tybOi4hjZFQ" && videos[0].cardId == "b")
        #expect(!videos[1].isYouTube && videos[1].title == "Video of 5 minutes of breathing")
    }

    @Test func aYouTubeAddressGivesItsVideoId() {
        func id(_ s: String) -> String? { YouTubeID.parse(URL(string: s)!) }
        #expect(id("https://www.youtube.com/watch?v=tybOi4hjZFQ") == "tybOi4hjZFQ")
        #expect(id("https://www.youtube.com/watch?v=tybOi4hjZFQ&t=30s") == "tybOi4hjZFQ")
        #expect(id("https://youtu.be/tybOi4hjZFQ?si=abc") == "tybOi4hjZFQ")
        #expect(id("https://m.youtube.com/embed/tybOi4hjZFQ") == "tybOi4hjZFQ")
        #expect(id("https://www.youtube.com/shorts/tybOi4hjZFQ") == "tybOi4hjZFQ")
        #expect(id("https://www.youtube.com/results?search_query=x") == nil)
        #expect(id("https://www.youtube.com/watch?v=short") == nil)
        #expect(id("https://example.com/watch?v=tybOi4hjZFQ") == nil)
        #expect(id("https://www.youtube.com.evil.test/watch?v=tybOi4hjZFQ") == nil)
    }

    // MARK: The member's habits, for search

    @Test func memberHabitsAreTheirOwnPlusTheTracksActionsNotAlreadyAmongThem() {
        var day = TrackDay(day: 4, titleEn: "Sleep")
        var a = TrackAction(key: "daylight", moment: .morning)
        a.habitBankId = "c-daylight"
        var b = TrackAction(key: "rule", moment: .evening)
        b.habitBankId = "c-321"
        day.actions = [a, b]
        var later = TrackDay(day: 10, titleEn: "Evening")
        var c = TrackAction(key: "book", moment: .evening)
        c.habitBankId = "c-book"
        later.actions = [c]
        let plan = HabitPlan(day: "2026-11-10", header: nil, phases: [], habits: [habit("h1", title: "Mine", card: "c-321")], completions: [])
        let cards = ["c-daylight": card("c-daylight", title: "Daylight first thing"), "c-321": card("c-321", title: "The 3-2-1 rule")]
        let habits = FoundationLibraryLogic.habits(plan: plan, days: [day, later], through: 4, cards: cards, locale: "en")
        #expect(habits.map(\.title) == ["Mine", "Daylight first thing"])      // day 10 is not here yet; c-321 is already "Mine"
        #expect(habits[1].target == .trackCard("c-daylight", face: "standard") && habits[1].moment == .morning)
        #expect(FoundationLibraryLogic.habits(plan: nil, days: [day], through: nil, cards: cards, locale: "en").isEmpty)
    }

    @Test func theTrackActionsCountUpToTodayAndThroughDay14AfterIt() {
        #expect(FoundationLibraryLogic.actionsThrough(status: status(day: 6)) == 6)
        #expect(FoundationLibraryLogic.actionsThrough(status: status(day: 20)) == 14)
        #expect(FoundationLibraryLogic.actionsThrough(status: nil) == nil)
    }
}
