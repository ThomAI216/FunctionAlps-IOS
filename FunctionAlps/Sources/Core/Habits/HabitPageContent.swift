import Foundation

/// A read on a habit page: titled, and soft-locked while it belongs to a track day still to come.
struct HabitPageRead: Sendable, Equatable, Identifiable {
    let slug: String
    let title: String
    /// The track day it opens on, when that is still to come.
    let opensOn: Int?
    var id: String { slug }
}

/// Everything a habit page lays out, assembled from what CM OS sent (the day's action, its `habit_bank` card, the
/// ticks). Pure: the page only draws it.
struct HabitPageContent: Sendable, Equatable {
    let key: String
    let title: String
    let moment: DayMoment
    let summary: String?
    let firstDay: Int
    /// nil = runs through the end of the track.
    let lastDay: Int?
    let today: Int
    let steps: [String]
    let reads: [HabitPageRead]
    let benefits: [String]
    let moves: [HabitMove]
    let video: LibraryVideo?
    let doneToday: Bool
    /// The action is on today's list, so "Done today" can tick it.
    let canTick: Bool
    /// nil on the habit's first day: no streak card yet.
    let streak: Streak?

    struct Streak: Sendable, Equatable {
        let run: Int
        let dots: [HabitDot]
    }

    /// "Day 4 onwards" / "Day 3 to 9".
    var whenText: String {
        if let lastDay {
            return String(localized: "habit.when.range", defaultValue: "Day \(firstDay) to \(lastDay)")
        }
        return String(localized: "habit.when.onwards", defaultValue: "Day \(firstDay) onwards")
    }

    /// The page for one action, or nil when the track does not list it.
    static func make(
        key: String, days: [TrackDay], cards: [String: ActionCardRow], activity: Set<TrackActivityItem>, today: Int,
        library: [LibraryArticle], locale: String
    ) -> HabitPageContent? {
        guard let span = HabitStreak.span(of: key, in: days) else { return nil }
        // The day's own version of the action (the latest day up to today that lists it, else the first that does).
        let listed = days.sorted { $0.day < $1.day }.compactMap { day in day.actions.first { $0.key == key }.map { (day.day, $0) } }
        guard let action = (listed.last { $0.0 <= today } ?? listed.first)?.1 else { return nil }
        let card = action.habitBankId.flatMap { cards[$0] }
        let resources = HabitResources.decode(card?.resources)
        let how = TrackLogic.text(action.howEn, action.howFr, locale: locale)

        // The reads: the card's articles first, then the ones the day ties to the action.
        var slugs: [(slug: String, title: String?)] = resources.articles.map { ($0.slug, $0.title) }
        for slug in action.reads where !slugs.contains(where: { $0.slug == slug }) { slugs.append((slug, nil)) }
        let catalog = Dictionary(library.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let reads = slugs.map { entry -> HabitPageRead in
            let known = catalog[entry.slug]
            let title = entry.title ?? known?.title ?? LibraryLogic.title(fromSlug: entry.slug)
            let opens = known.flatMap { FoundationLibraryLogic.opensOn($0, today: today) }
            return HabitPageRead(slug: entry.slug, title: title, opensOn: opens)
        }

        let title = TrackLogic.actionTitle(action, card: card, locale: locale)
        let video = resources.video.map {
            LibraryVideo(url: $0.url, title: $0.title ?? title, cardId: card?.id)
        }
        let done = HabitStreak.doneDays(key: key, activity: activity)
        let last: Int? = span.last >= 14 ? nil : span.last
        let streak = HabitStreak.showsStreak(first: span.first, today: today)
            ? Streak(run: HabitStreak.current(done: done, first: span.first, last: last, today: today),
                     dots: HabitStreak.dots(done: done, first: span.first, last: last, today: today))
            : nil
        let onToday = days.first { $0.day == today }?.actions.contains { $0.key == key } == true
        return HabitPageContent(
            key: key, title: title, moment: action.dayMoment,
            summary: card.flatMap { ActionCardLogic.pick($0.description, $0.descriptionFr, locale: locale) } ?? how,
            firstDay: span.first, lastDay: last, today: today,
            steps: ActionCardLogic.steps(card.flatMap { ActionCardLogic.pick($0.howMd, $0.howMdFr, locale: locale) }),
            reads: reads, benefits: resources.benefits, moves: resources.moves, video: video,
            doneToday: done.contains(today), canTick: onToday, streak: streak
        )
    }
}
