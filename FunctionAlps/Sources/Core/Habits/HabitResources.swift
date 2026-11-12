import Foundation

/// One "what it tends to move" chip: the practice's word and a direction. The direction is shown by an arrow AND by
/// words, never by colour alone (rule 10).
struct HabitMove: Sendable, Equatable, Identifiable {
    enum Direction: String, Sendable { case up, down }
    let label: String
    let direction: Direction
    var id: String { label }

    var arrow: String { direction == .up ? "↑" : "↓" }
    /// "Raises sleep" / "Lowers stress", for VoiceOver.
    var spoken: String {
        direction == .up
            ? String(localized: "habit.move.up", defaultValue: "Tends to raise \(label)")
            : String(localized: "habit.move.down", defaultValue: "Tends to lower \(label)")
    }
}

/// A read a habit points to (`{kind: "article", slug, title}`).
struct HabitArticle: Sendable, Equatable, Identifiable {
    let slug: String
    let title: String?
    var id: String { slug }
}

/// What a `habit_bank.resources` array holds, typed (CM OS, 2026-11-08): articles, a video, the benefits to look for,
/// and the moves. A kind this build does not know is ignored, a malformed entry too — never the whole card.
struct HabitResources: Sendable, Equatable {
    var articles: [HabitArticle] = []
    var video: (url: URL, title: String?)?
    var benefits: [String] = []
    var moves: [HabitMove] = []

    static func == (l: Self, r: Self) -> Bool {
        l.articles == r.articles && l.video?.url == r.video?.url && l.video?.title == r.video?.title
            && l.benefits == r.benefits && l.moves == r.moves
    }

    static func decode(_ raw: [ActionCardRow.RawLink]?) -> HabitResources {
        var out = HabitResources()
        for entry in raw ?? [] {
            switch entry.kind {
            case "article":
                guard let slug = entry.slug?.trimmed.nonEmpty, !out.articles.contains(where: { $0.slug == slug }) else { continue }
                out.articles.append(HabitArticle(slug: slug, title: entry.title?.trimmed.nonEmpty))
            case "video":
                guard out.video == nil, let string = entry.url?.trimmed, string.lowercased().hasPrefix("https://"), let url = URL(string: string) else { continue }
                // A YouTube address the player cannot read (a search page, a playlist) is left out, as in the Library.
                if YouTubeID.isYouTubeHost(url), YouTubeID.parse(url) == nil { continue }
                out.video = (url, entry.title?.trimmed.nonEmpty)
            case "benefits":
                for item in entry.items ?? [] {
                    if let text = item.label.trimmed.nonEmpty, !out.benefits.contains(text) { out.benefits.append(text) }
                }
            case "moves":
                for item in entry.items ?? [] {
                    guard let label = item.label.trimmed.nonEmpty, let dir = item.dir.flatMap(HabitMove.Direction.init(rawValue:)),
                          !out.moves.contains(where: { $0.label == label }) else { continue }
                    out.moves.append(HabitMove(label: label, direction: dir))
                }
            default:
                continue
            }
        }
        return out
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
