import Foundation

// Action cards — what a member opens from "Today's actions" (owner, 2026-10-02).
//
// A card is a `habit_bank` row the practice authors in CLINICAL → Action cards (steps, gentler and further
// versions, a video, a YouTube keyword, the why, a library article) and publishes; a prescribed habit points at
// it through `habits.habit_bank_id`. Members read cards LIVE (RLS `habit_bank_member_select` = active): an
// edit the practice publishes reaches every member who has the card. Every word on a card is the practice's
// (rule 6) — the app only lays it out, in the language it is drawn in, falling back to the other when a field
// has not been translated.

/// Which page the card opens on: a breathing pacer, a movement with its demonstration, a routine of steps…
enum ActionCardKind: String, Sendable, Equatable, CaseIterable {
    case breath, movement, routine, nutrition, mind, learn

    var label: String {
        switch self {
        case .breath: String(localized: "action.kind.breath", defaultValue: "Breathwork")
        case .movement: String(localized: "action.kind.movement", defaultValue: "Movement")
        case .routine: String(localized: "action.kind.routine", defaultValue: "Routine")
        case .nutrition: String(localized: "action.kind.nutrition", defaultValue: "Nutrition")
        case .mind: String(localized: "action.kind.mind", defaultValue: "Mind")
        case .learn: String(localized: "action.kind.learn", defaultValue: "Learn")
        }
    }

    var symbol: String {
        switch self {
        case .breath: "wind"
        case .movement: "figure.walk"
        case .routine: "checklist"
        case .nutrition: "fork.knife"
        case .mind: "brain.head.profile"
        case .learn: "book"
        }
    }
}

/// One entry of the card's `resources` list.
enum ActionCardLink: Sendable, Equatable {
    case video(url: URL, title: String?)
    case youtube(query: String)
    case article(slug: String, title: String?)
}

/// One `habit_bank` row as members may read it (published = active).
struct ActionCardRow: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    var pillar: String?
    var cardKind: String?
    var durationMin: Int?
    var title: String
    var titleFr: String?
    var description: String?
    var descriptionFr: String?
    var easyTitle: String?
    var easyTitleFr: String?
    var easyDescription: String?
    var easyDescriptionFr: String?
    var revTitle: String?
    var revTitleFr: String?
    var revDescription: String?
    var revDescriptionFr: String?
    var howMd: String?
    var howMdFr: String?
    var generalWhy: String?
    var generalWhyFr: String?
    var imageUrl: String?
    var imageAlt: String?
    /// The moment the card suggests (`morning` · `midday` · `evening`; nil = anytime) and its RRULE (nil = daily) —
    /// what a member's own habit starts with when they add the card from the bank.
    var defaultSlot: String?
    var frequencyRule: String?
    /// A foundation card: members may add it to their own plan from the action bank.
    var memberCanAdd: Bool?
    /// Kept raw: a malformed entry is dropped by `ActionCardLogic.links`, never fails the whole card.
    var resources: [RawLink]?

    /// The columns the app reads — Core/API only (rule 2) uses this list.
    static let columns = "id,pillar,card_kind,duration_min,title,title_fr,description,description_fr,easy_title,easy_title_fr,"
        + "easy_description,easy_description_fr,rev_title,rev_title_fr,rev_description,rev_description_fr,how_md,how_md_fr,"
        + "general_why,general_why_fr,image_url,image_alt,resources,default_slot,frequency_rule,member_can_add"

    struct RawLink: Decodable, Sendable, Equatable {
        var kind: String?
        var url: String?
        var query: String?
        var slug: String?
        var title: String?
    }
}

/// A card's content in one language, ready to lay out.
struct ActionCardContent: Sendable, Equatable {
    var kind: ActionCardKind?
    var durationMin: Int?
    var title: String
    var description: String?
    var easyTitle: String?
    var easyDescription: String?
    var furtherTitle: String?
    var furtherDescription: String?
    var steps: [String]
    var why: String?
    var imageURL: URL?
    var imageAlt: String?
    var links: [ActionCardLink]

    var video: (url: URL, title: String?)? {
        for link in links { if case .video(let url, let title) = link { return (url, title) } }
        return nil
    }
    var youtubeQuery: String? {
        for link in links { if case .youtube(let query) = link { return query } }
        return nil
    }
    var article: (slug: String, title: String?)? {
        for link in links { if case .article(let slug, let title) = link { return (slug, title) } }
        return nil
    }
}

enum ActionCardLogic {
    /// The language's text, else the other language's — a field the practice has not translated yet still shows.
    static func pick(_ en: String?, _ fr: String?, locale: String) -> String? {
        let first = locale == "fr" ? fr : en, second = locale == "fr" ? en : fr
        for value in [first, second] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }

    /// The steps of `how_md`: one per line, list markers (`1.`, `1)`, `-`, `*`, `•`) stripped, blank lines dropped —
    /// the same rule as CLINICAL's preview (`cardSteps`), so the member sees what the clinician saw.
    static func steps(_ howMd: String?) -> [String] {
        guard let howMd else { return [] }
        return howMd.components(separatedBy: .newlines).compactMap { line in
            let stripped = line.replacingOccurrences(of: #"^\s*(?:\d+[.)]|[-*•])\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? nil : stripped
        }
    }

    /// The typed links; anything malformed (no https URL, empty query or slug, unknown kind) is dropped.
    static func links(_ raw: [ActionCardRow.RawLink]?) -> [ActionCardLink] {
        (raw ?? []).compactMap { link in
            let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            switch link.kind {
            case "video":
                guard let string = link.url?.trimmingCharacters(in: .whitespaces), string.lowercased().hasPrefix("https://"),
                      let url = URL(string: string) else { return nil }
                return .video(url: url, title: title)
            case "youtube":
                guard let query = link.query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
                return .youtube(query: query)
            case "article":
                guard let slug = link.slug?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
                return .article(slug: slug, title: title)
            default:
                return nil
            }
        }
    }

    /// What the app opens for a YouTube keyword: YouTube's own search (the app or Safari), nothing embedded.
    static func youtubeSearchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components?.url
    }

    /// The card in one language. `habit` supplies what the card leaves out: the habit's own title (the
    /// clinician's words for THIS member lead), and its description and versions when the card has none. Without a
    /// habit (a bank card the member is reading before adding it) the card speaks for itself.
    static func content(card: ActionCardRow?, habit: HabitRow?, locale: String) -> ActionCardContent {
        guard let card else {
            return ActionCardContent(
                kind: nil, durationMin: nil, title: habit?.title ?? "", description: habit?.description?.nilIfEmpty,
                easyTitle: habit?.easyTitle?.nilIfEmpty, easyDescription: habit?.easyDescription?.nilIfEmpty,
                furtherTitle: habit?.revTitle?.nilIfEmpty, furtherDescription: habit?.revDescription?.nilIfEmpty,
                steps: [], why: nil, imageURL: nil, imageAlt: nil, links: []
            )
        }
        let image = card.imageUrl.flatMap { $0.lowercased().hasPrefix("https://") ? URL(string: $0) : nil }
        let cardTitle = pick(card.title, card.titleFr, locale: locale) ?? card.title
        return ActionCardContent(
            kind: card.cardKind.flatMap(ActionCardKind.init(rawValue:)),
            durationMin: card.durationMin.flatMap { (1...240).contains($0) ? $0 : nil },
            title: habit?.title.nilIfEmpty ?? cardTitle,
            description: pick(card.description, card.descriptionFr, locale: locale) ?? habit?.description?.nilIfEmpty,
            easyTitle: pick(card.easyTitle, card.easyTitleFr, locale: locale) ?? habit?.easyTitle?.nilIfEmpty,
            easyDescription: pick(card.easyDescription, card.easyDescriptionFr, locale: locale) ?? habit?.easyDescription?.nilIfEmpty,
            furtherTitle: pick(card.revTitle, card.revTitleFr, locale: locale) ?? habit?.revTitle?.nilIfEmpty,
            furtherDescription: pick(card.revDescription, card.revDescriptionFr, locale: locale) ?? habit?.revDescription?.nilIfEmpty,
            steps: steps(pick(card.howMd, card.howMdFr, locale: locale)),
            why: pick(card.generalWhy, card.generalWhyFr, locale: locale),
            imageURL: image,
            imageAlt: card.imageAlt?.nilIfEmpty,
            links: links(card.resources)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
