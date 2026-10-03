#if DEBUG
import Foundation

/// The show in the showcase screenshots: the first week (Tuesday 6 → Friday 9 October 2026), seen on the Friday
/// morning, with the next live on Saturday 10 October at 12:30 and the movement experiment at day 3 of 7. Sample
/// text only — the real episodes come from the CLINICAL library API, and none of this exists outside Debug.
extension ShowcaseData {
    static let showEpisodeSlug = "showcase-movement-foundation"

    /// Friday 9 October 2026, 09:41 in Zurich.
    static var showNow: Date { ShowLogic.zonedDate(day: "2026-10-09", time: "09:41") ?? Date() }

    private static func showAt(_ day: String) -> Date { ShowLogic.zonedDate(day: day, time: "12:30") ?? Date() }

    private static let allPieces = ShowEpisodeHas(research: true, article: true, guide: true, faq: true, showNotes: true, video: false)
    private static let sampleAudio = URL(string: "https://example.com/showcase/episode.m4a")

    static let showCards: [ShowEpisodeCard] = [
        ShowEpisodeCard(slug: "showcase-understanding-stress", number: 4, title: ShowText(en: "Understanding stress", fr: "Comprendre le stress"),
                        track: .mental, startsAt: showAt("2026-10-09"), durationSeconds: 31 * 60, audioURL: sampleAudio, has: allPieces),
        ShowEpisodeCard(slug: "showcase-why-sleep-matters", number: 3, title: ShowText(en: "Why sleep matters", fr: "Pourquoi le sommeil compte"),
                        track: .sleep, startsAt: showAt("2026-10-08"), durationSeconds: 29 * 60, audioURL: sampleAudio, has: allPieces),
        ShowEpisodeCard(slug: "showcase-nutrition-foundations", number: 2, title: ShowText(en: "Nutrition foundations", fr: "Les bases de la nutrition"),
                        track: .nutrition, startsAt: showAt("2026-10-07"), durationSeconds: 30 * 60, audioURL: sampleAudio, has: allPieces),
        ShowEpisodeCard(slug: showEpisodeSlug, number: 1, title: ShowText(en: "Movement as a foundation of health", fr: "Le mouvement, fondation de la santé"),
                        track: .movement, startsAt: showAt("2026-10-06"), durationSeconds: 30 * 60, audioURL: sampleAudio, has: allPieces),
    ]

    static func showLibrary() -> ShowLibrary {
        let live = ShowUpcoming(slug: "showcase-live-2026-10-10", kind: .live, number: nil,
                                title: ShowText(en: "The week in review, your questions", fr: "La semaine en revue, vos questions"),
                                track: .cross, startsAt: showAt("2026-10-10"), endsAt: showAt("2026-10-10").addingTimeInterval(45 * 60))
        return ShowLibrary(series: nil, episodes: showCards, upcoming: [live])
    }

    /// Days 1 and 2 of the movement experiment, marked on the Wednesday and the Thursday evening.
    static func showProgress() -> [ShowProgressRow] {
        [
            ShowProgressRow(contentSlug: ShowLogic.experimentKey(slug: showEpisodeSlug, day: 1),
                            completedAt: ShowLogic.zonedDate(day: "2026-10-07", time: "18:10")),
            ShowProgressRow(contentSlug: ShowLogic.experimentKey(slug: showEpisodeSlug, day: 2),
                            completedAt: ShowLogic.zonedDate(day: "2026-10-08", time: "13:20")),
        ]
    }

    static func showEpisode(slug: String) -> ShowEpisode? {
        guard let card = showCards.first(where: { $0.slug == slug }) else { return nil }
        let notes = ShowNotes(
            summary: "Sample notes for the showcase. Three things to take away, then this week's experiment.",
            chapters: [
                ShowChapter(start: "00:00:00", title: "Welcome"),
                ShowChapter(start: "00:03:40", title: "Why it matters"),
                ShowChapter(start: "00:11:15", title: "The experiment"),
                ShowChapter(start: "00:22:30", title: "Questions"),
            ],
            keyActions: ["Move a little every day", "Break up long sitting", "Pick a walk you enjoy"]
        )
        let research = ShowResearch(
            synthesis: .init(know: ["Sample finding the evidence agrees on."], likely: ["Sample finding that is probable."],
                             uncertain: ["Sample question still open."]),
            references: [
                ShowReference(pmid: "", title: "Showcase sample source A", journal: "Sample journal", year: 2024, authors: "Sample A, et al."),
                ShowReference(pmid: "", title: "Showcase sample source B", journal: "Sample journal", year: 2023, authors: "Sample B, et al."),
            ]
        )
        let days = (1...7).map { ShowGuide.Day(day: $0, action: $0 <= 5 ? "walk 10 min after lunch" : "walk 15 min after lunch") }
        let guide = ShowGuide(
            summary: "Sample guide.", keyActions: [],
            experiment: .init(title: "Walk after lunch", goal: "A short walk after lunch, every day for a week.", days: days),
            reflection: ["What did you notice in your afternoons?"]
        )
        let article = ShowArticle(
            title: card.title.en ?? "",
            intro: "Sample article for the showcase.",
            sections: [.init(heading: "Sample section", body: "Sample paragraph.")],
            takeaways: ["Sample takeaway."],
            references: []
        )
        let faq = ShowFaq(items: [
            .init(question: "Sample question one?", answer: "Sample answer."),
            .init(question: "Sample question two?", answer: "Sample answer."),
        ])
        return ShowEpisode(
            card: card, member: true,
            showNotes: ShowBilingual(en: notes, fr: notes), videoURL: nil,
            research: ShowBilingual(en: research, fr: research),
            article: ShowBilingual(en: article, fr: article),
            guide: ShowBilingual(en: guide, fr: guide),
            faq: ShowBilingual(en: faq, fr: faq)
        )
    }
}
#endif
