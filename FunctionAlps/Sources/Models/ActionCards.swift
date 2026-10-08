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

/// How a card's video plays (owner, 2026-10-08: the practice's demonstrations are on YouTube for now). A YouTube
/// link plays inside the card, in YouTube's own player (its terms allow no other); any other https link opens
/// outside the app, as before. The paid video host that comes later (HLS played in AVKit, signed for members-only
/// cards) is one more case here — the card and its data stay as they are.
enum ActionCardVideoSource: Sendable, Equatable {
    case youtube(id: String, start: Int?)
    case link(URL)
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
    /// The next level of this action on its evolution ladder (`habit_bank.next_level_id`); nil = top of its ladder.
    var nextLevelId: String?

    /// The columns the app reads — Core/API only (rule 2) uses this list.
    static let columns = "id,pillar,card_kind,duration_min,title,title_fr,description,description_fr,easy_title,easy_title_fr,"
        + "easy_description,easy_description_fr,rev_title,rev_title_fr,rev_description,rev_description_fr,how_md,how_md_fr,"
        + "general_why,general_why_fr,image_url,image_alt,resources,default_slot,frequency_rule,member_can_add,next_level_id"

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

    /// The video link as the app plays it: a YouTube video inside the card, anything else outside the app.
    static func videoSource(_ url: URL) -> ActionCardVideoSource {
        if let video = youtubeVideo(url) { return .youtube(id: video.id, start: video.start) }
        return .link(url)
    }

    /// The YouTube video a pasted link names — `watch?v=`, `youtu.be/`, `shorts/`, `embed/`, `live/` on youtube.com,
    /// m.youtube.com or youtube-nocookie.com — and where it starts (`t` or `start`: `90`, `90s`, `1m30s`). Nil for
    /// anything else, a channel or playlist link included.
    static func youtubeVideo(_ url: URL) -> (id: String, start: Int?)? {
        guard url.scheme?.lowercased() == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems ?? []
        let candidate: String?
        switch host {
        case "youtu.be":
            candidate = path.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com":
            if path == ["watch"] {
                candidate = query.first { $0.name == "v" }?.value
            } else if path.count >= 2, ["shorts", "embed", "live"].contains(path[0]) {
                candidate = path[1]
            } else {
                candidate = nil
            }
        default:
            candidate = nil
        }
        guard let id = candidate, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        let start = query.first { $0.name == "t" || $0.name == "start" }?.value.flatMap(youtubeSeconds)
        return (id, start)
    }

    /// `90`, `90s`, `1m30s`, `1h2m3s` → seconds; nil when unreadable or zero.
    static func youtubeSeconds(_ value: String) -> Int? {
        let text = value.lowercased()
        if let seconds = Int(text) { return seconds > 0 ? seconds : nil }
        guard let match = text.wholeMatch(of: /(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/) else { return nil }
        let seconds = (Int(match.1 ?? "0") ?? 0) * 3600 + (Int(match.2 ?? "0") ?? 0) * 60 + (Int(match.3 ?? "0") ?? 0)
        return seconds > 0 ? seconds : nil
    }

    /// YouTube's embedded player for the video: it starts on load (the member has just tapped play), plays inside
    /// the card, ends on the practice's own videos only (`rel=0`), with its controls and captions in the app's
    /// language.
    static func youtubeEmbedURL(id: String, start: Int?, locale: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/embed/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "hl", value: locale),
            URLQueryItem(name: "cc_lang_pref", value: locale),
        ] + (start.map { [URLQueryItem(name: "start", value: String($0))] } ?? [])
        return components?.url
    }

    /// Who is embedding the player, as YouTube requires of an app (the Referer): `https://` + the bundle id in lower
    /// case. Without it the player refuses to play.
    static func youtubeClientOrigin(bundleID: String) -> URL? {
        URL(string: "https://\(bundleID.lowercased())")
    }

    /// The page the card's web view loads: the player filling it, on black.
    static func youtubePlayerHTML(embed: URL, title: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        let source = embed.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        return """
        <!doctype html><html><head><meta charset="utf-8">\
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">\
        <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}\
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head>\
        <body><iframe src="\(source)" title="\(escapedTitle)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" \
        allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
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
