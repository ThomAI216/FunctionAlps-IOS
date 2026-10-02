import Foundation
import Testing
@testable import FunctionAlps

@Suite("Action cards — the practice's card around the clinician's habit")
struct ActionCardTests {
    private func habit(title: String = "Evening breathing", description: String? = "Before bed", easy: String? = nil,
                       rev: String? = nil, card: String? = "b-1") -> HabitRow {
        HabitRow(id: "h-1", carePlanItemId: "i-1", title: title, description: description, frequencyRule: "FREQ=DAILY",
                 status: "active", source: "prescribed", pillar: "sleep", slot: "evening", appearsAfterHabitId: nil,
                 easyTitle: easy, easyDescription: nil, revTitle: rev, revDescription: nil,
                 createdAt: "2026-09-01T07:00:00+00:00", habitBankId: card)
    }

    private func card(_ change: (inout ActionCardRow) -> Void = { _ in }) -> ActionCardRow {
        var row = ActionCardRow(id: "b-1", title: "4-7-8 breathing")
        row.cardKind = "breath"
        row.durationMin = 5
        row.titleFr = "Respiration 4-7-8"
        row.description = "A slow breath to wind down."
        row.descriptionFr = "Une respiration lente."
        row.easyTitle = "3 slow breaths"
        row.howMd = "1. Sit\n2) In for 4\n\n- Hold 7\n• Out for 8"
        row.howMdFr = "1. Asseyez-vous\n2. Inspirez 4"
        row.generalWhy = "Slow breathing can help you settle."
        row.imageUrl = "https://example.supabase.co/storage/v1/object/public/content-public/action-cards/a.webp"
        row.resources = [
            .init(kind: "video", url: "https://youtu.be/abc", title: "Demo"),
            .init(kind: "youtube", query: "  478 breathing "),
            .init(kind: "article", slug: "sleep-basics", title: "Sleep basics"),
        ]
        change(&row)
        return row
    }

    @Test func picksTheAppLanguageThenFallsBackToTheOther() {
        #expect(ActionCardLogic.pick("Breathe", "Respirez", locale: "fr") == "Respirez")
        #expect(ActionCardLogic.pick("Breathe", "Respirez", locale: "en") == "Breathe")
        #expect(ActionCardLogic.pick("Breathe", "  ", locale: "fr") == "Breathe")
        #expect(ActionCardLogic.pick(nil, "Respirez", locale: "en") == "Respirez")
        #expect(ActionCardLogic.pick(nil, nil, locale: "en") == nil)
    }

    @Test func stepsDropListMarkersAndBlankLines_likeClinicalsPreview() {
        #expect(ActionCardLogic.steps("1. Sit\n2) In for 4\n\n- Hold 7\n* Out\n• Again\nPlain") == ["Sit", "In for 4", "Hold 7", "Out", "Again", "Plain"])
        #expect(ActionCardLogic.steps(nil).isEmpty)
        #expect(ActionCardLogic.steps("  \n ").isEmpty)
    }

    @Test func malformedLinksAreDropped() {
        let links = ActionCardLogic.links([
            .init(kind: "video", url: "http://insecure.example"),
            .init(kind: "video", url: "javascript:alert(1)"),
            .init(kind: "youtube", query: " "),
            .init(kind: "article", slug: ""),
            .init(kind: "podcast", url: "https://x.example"),
            .init(kind: "video", url: "https://vimeo.com/1", title: " "),
        ])
        #expect(links == [.video(url: URL(string: "https://vimeo.com/1")!, title: nil)])
        #expect(ActionCardLogic.links(nil).isEmpty)
    }

    @Test func youtubeOpensASearchForTheKeyword() {
        #expect(ActionCardLogic.youtubeSearchURL("respiration 4-7-8")?.absoluteString == "https://www.youtube.com/results?search_query=respiration%204-7-8")
    }

    @Test func theCardInFrench_withTheHabitsOwnTitleLeading() {
        let content = ActionCardLogic.content(card: card(), habit: habit(), locale: "fr")
        #expect(content.kind == .breath)
        #expect(content.durationMin == 5)
        #expect(content.title == "Evening breathing")
        #expect(content.description == "Une respiration lente.")
        #expect(content.steps == ["Asseyez-vous", "Inspirez 4"])
        // Not translated yet → the English text, rather than nothing.
        #expect(content.why == "Slow breathing can help you settle.")
        #expect(content.easyTitle == "3 slow breaths")
        #expect(content.video?.url.absoluteString == "https://youtu.be/abc")
        #expect(content.youtubeQuery == "478 breathing")
        #expect(content.article?.slug == "sleep-basics")
        #expect(content.imageURL != nil)
    }

    @Test func outOfRangeDurationsAndUnknownKindsAreIgnored() {
        let content = ActionCardLogic.content(card: card { $0.durationMin = 900; $0.cardKind = "yoga"; $0.imageUrl = "http://x" }, habit: habit(), locale: "en")
        #expect(content.durationMin == nil)
        #expect(content.kind == nil)
        #expect(content.imageURL == nil)
    }

    @Test func aHabitWithoutACardOpensOnItsOwnWords() {
        let content = ActionCardLogic.content(card: nil, habit: habit(easy: "Three breaths", rev: "Eight cycles", card: nil), locale: "fr")
        #expect(content.title == "Evening breathing")
        #expect(content.description == "Before bed")
        #expect(content.easyTitle == "Three breaths")
        #expect(content.furtherTitle == "Eight cycles")
        #expect(content.steps.isEmpty && content.links.isEmpty && content.kind == nil)
    }

    @Test func theCardsVersionsWinOverTheHabitsOnlyWhenWritten() {
        let content = ActionCardLogic.content(card: card { $0.easyTitle = nil }, habit: habit(easy: "Habit's gentle one"), locale: "en")
        #expect(content.easyTitle == "Habit's gentle one")
    }
}
