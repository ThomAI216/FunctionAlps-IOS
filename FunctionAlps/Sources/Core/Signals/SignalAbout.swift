import CoreGraphics
import Foundation

// The logic behind the "About <signal>" pages (owner, 2026-11-11). Everything here is pure: it styles, matches and lays
// out what the database content says; it never words anything. The explanation text is `signal_explanations`.

// MARK: Which signals have a page

/// The seven things that have an "About" page: the six check-in signals and the Functional score. The route carries the raw
/// string (`Route.signalAbout`), so a link or a row can never ask for a page that does not exist.
enum SignalAboutKey: String, CaseIterable, Sendable, Hashable {
    case sleep, energy, focus, mood, stress, digestion, score

    /// The six signals the mini map draws around its centre.
    static let signals: [SignalAboutKey] = [.sleep, .energy, .focus, .mood, .stress, .digestion]

    var trendSignal: TrendSignal? { TrendSignal(rawValue: rawValue) }
    /// One colour per signal (the Trends mockup's); the score is the brand forest.
    var tintHex: UInt32 { trendSignal?.tintHex ?? 0x2E5438 }
    /// The word on this signal's node of the map.
    var nodeName: String { trendSignal?.title ?? String(localized: "signal.about.scoreNode", defaultValue: "Score") }

    /// "Learn about sleep" — one string per signal so every language can agree its article.
    var linkTitle: String {
        switch self {
        case .sleep: String(localized: "signal.about.link.sleep", defaultValue: "Learn about sleep")
        case .energy: String(localized: "signal.about.link.energy", defaultValue: "Learn about energy")
        case .focus: String(localized: "signal.about.link.focus", defaultValue: "Learn about focus")
        case .mood: String(localized: "signal.about.link.mood", defaultValue: "Learn about mood")
        case .stress: String(localized: "signal.about.link.stress", defaultValue: "Learn about stress")
        case .digestion: String(localized: "signal.about.link.digestion", defaultValue: "Learn about digestion")
        case .score: String(localized: "signal.about.link.score", defaultValue: "Learn about your functional score")
        }
    }
}

// MARK: Evidence → badge and line style

/// How strong the evidence behind a line is, as the practice rated it. Strong = a filled green badge, moderate = blue,
/// emerging = purple (owner, 2026-11-11). The WORD is always shown, so colour is never the only signal (rule 10).
enum SignalEvidence: String, Sendable, CaseIterable, Equatable {
    case strong, moderate, emerging

    /// Tolerant: "moderate-strong" and "strong-moderate" read as moderate; a blank or unknown level as emerging
    /// (never claim more than was said).
    init(raw: String?) {
        let text = (raw ?? "").lowercased()
        if text.contains("moderate") { self = .moderate }
        else if text.hasPrefix("strong") { self = .strong }
        else { self = .emerging }
    }

    var word: String {
        switch self {
        case .strong: String(localized: "signal.evidence.strong", defaultValue: "Strong")
        case .moderate: String(localized: "signal.evidence.moderate", defaultValue: "Moderate")
        case .emerging: String(localized: "signal.evidence.emerging", defaultValue: "Emerging")
        }
    }

    struct BadgeStyle: Equatable, Sendable {
        let backgroundHex: UInt32
        let backgroundOpacity: Double
        let foregroundHex: UInt32
    }

    var badge: BadgeStyle {
        switch self {
        case .strong: BadgeStyle(backgroundHex: 0x4A8A5C, backgroundOpacity: 1, foregroundHex: 0xFFFFFF)
        case .moderate: BadgeStyle(backgroundHex: 0x4F86C6, backgroundOpacity: 0.18, foregroundHex: 0x1D4E89)
        case .emerging: BadgeStyle(backgroundHex: 0x8E7CC3, backgroundOpacity: 0.18, foregroundHex: 0x5B4A9E)
        }
    }

    /// The mini map's line for this evidence: solid · dashed · dotted.
    struct LineStyle: Equatable, Sendable {
        let width: CGFloat
        let dash: [CGFloat]
        let roundCap: Bool
    }

    var line: LineStyle {
        switch self {
        case .strong: LineStyle(width: 1.8, dash: [], roundCap: false)
        case .moderate: LineStyle(width: 1.6, dash: [5, 3.2], roundCap: false)
        case .emerging: LineStyle(width: 1.9, dash: [0.1, 3.6], roundCap: true)
        }
    }
}

/// "What it feels like": the good end green, the other end red-orange (owner, 2026-11-11). The words stay (rule 10).
enum SignalFeelsStyle {
    static let highTintHex: UInt32 = 0x4A8A5C
    static let highTextHex: UInt32 = 0x2E5438
    static let lowTintHex: UInt32 = 0xD9622B
    static let lowTextHex: UInt32 = 0x9A3F14
}

// MARK: "+ Add to my day" — a hint from the content to a card of the action bank

/// The content's `habit_hint` is matched to a card the practice already wrote in the action bank (`habit_bank`, cards
/// members may add) — never to a habit the app makes up. The tokens below are only search words for that match. No match
/// → the caller opens the action bank itself.
enum SignalActionMatch {
    /// Per hint: word starts found in a card's title (English or French). A card matches when its title holds ANY of them.
    static let keywords: [String: [String]] = [
        "walk": ["walk", "marche", "promenade"],
        "walk_after_meal": ["after lunch", "after dinner", "after a meal", "after meal", "après le déjeuner", "après le dîner", "après le repas"],
        "daylight": ["daylight", "morning light", "outside in", "lumière du jour", "lumière du matin"],
        "caffeine": ["caffeine", "coffee", "caféine", "café"],
        "caffeine_cutoff": ["caffeine", "coffee", "caféine", "café"],
        "wind_down": ["wind down", "wind-down", "screens", "écrans", "routine du soir", "evening routine"],
        "wake_time": ["wake time", "wake-up", "same time", "heure de lever", "réveil"],
        "bedtime": ["bedtime", "coucher"],
        "breathwork": ["breath", "sigh", "respir", "souffle", "soupir"],
        "protein": ["protein", "protéine"],
        "protein_breakfast": ["protein breakfast", "protein-rich breakfast", "breakfast", "petit-déjeuner", "petit déjeuner"],
        "fibre": ["fibre", "fiber", "vegetable", "légume"],
        "hydration": ["water", "hydrat", "eau"],
        "movement_break": ["exercise snack", "movement break", "mouvement", "stretch", "étirement"],
        "slow_eating": ["eat slowly", "chew", "mastic", "manger lentement", "slow eating"],
        "gratitude": ["gratitude", "grateful", "good things", "reconnaissance"],
        "social": ["friend", "social", "amis"],
        // The morning check-in's end screen (2026-11-12) asks for these three as well.
        "nsdr": ["nsdr", "yoga nidra", "deep rest", "repos profond"],
        "nap": ["nap", "sieste"],
        "meditation": ["meditat", "méditat"],
    ]

    /// The first bank card (in the bank's order) whose title or its other-language title holds a keyword of the hint.
    static func card(for hint: String?, in cards: [ActionCardRow]) -> ActionCardRow? {
        guard let hint = hint?.lowercased(), let words = keywords[hint] else { return nil }
        let wanted = words.map(fold)
        return cards.first { card in
            [card.title, card.titleFr].compactMap { $0 }.contains { title in
                let padded = " " + fold(title)
                return wanted.contains { padded.contains(" " + $0) }
            }
        }
    }

    /// Lowercased, accents folded, hyphens and apostrophes read as spaces: "Après" finds "apres", "Wind-down" finds
    /// "wind down", "d’eau" has the word "eau".
    private static func fold(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for mark in ["-", "'", "’"] { folded = folded.replacingOccurrences(of: mark, with: " ") }
        return folded
    }
}

// MARK: "Related reading" — library items whose pillar matches the signal

enum SignalRelated {
    /// The library's pillar keys (`LibraryLogic.pillarTopics`) that speak to each signal. The score has none: its page hides the block.
    static func topics(for key: SignalAboutKey) -> Set<String> {
        switch key {
        case .sleep: ["sommeil"]
        case .energy: ["energie", "nutrition"]
        case .focus: ["energie", "stress"]
        case .mood: ["stress", "mouvement"]
        case .stress: ["stress"]
        case .digestion: ["intestin", "nutrition"]
        case .score: []
        }
    }

    /// Up to `limit` open reads whose pillar matches, the signal's own pillar first, then in the list's order.
    static func articles(for key: SignalAboutKey, in list: [LibraryArticle], limit: Int = 2) -> [LibraryArticle] {
        let wanted = topics(for: key)
        guard !wanted.isEmpty else { return [] }
        let matching = list.filter { !$0.locked && ($0.topicKey.map(wanted.contains) ?? false) }
        let order = ["sommeil", "energie", "stress", "intestin", "nutrition", "mouvement"]
        let ranked = matching.enumerated().sorted { l, r in
            let a = order.firstIndex(of: l.element.topicKey ?? "") ?? order.count
            let b = order.firstIndex(of: r.element.topicKey ?? "") ?? order.count
            return a == b ? l.offset < r.offset : a < b
        }
        return ranked.prefix(max(0, limit)).map { $0.element }
    }
}

// MARK: The mini "How it connects" map — geometry only

/// The map's drawing, as numbers: this signal in the centre, the other signals on an ellipse around it, one curved arrow
/// per connection of the content (the Trends mockup's layout, in a 358-wide design space; the view scales it).
struct SignalMapLayout: Equatable, Sendable {
    static let baseWidth: CGFloat = 358

    struct Node: Equatable, Sendable {
        let key: String
        let isCentre: Bool
        let center: CGPoint
        let half: CGSize
    }

    struct Head: Equatable, Sendable {
        let tip: CGPoint
        let left: CGPoint
        let right: CGPoint
    }

    struct Edge: Equatable, Sendable {
        let from: String
        let to: String
        /// The curve is a quadratic Bézier from `start` to `end` (already stopped short of the arrowhead), bent through `control`.
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let heads: [Head]
        let label: String
        let labelPoint: CGPoint
        let evidence: SignalEvidence
        let bothEnds: Bool
    }

    let size: CGSize
    let nodes: [Node]
    let edges: [Edge]

    private static let others = SignalAboutKey.signals.map(\.rawValue)

    static func make(centre: String, connections: [SignalExplanation.Connection]) -> SignalMapLayout {
        let isScore = centre == SignalAboutKey.score.rawValue
        let ring = isScore ? others : others.filter { $0 != centre }
        let height: CGFloat = isScore ? 330 : 318
        let cx: CGFloat = baseWidth / 2
        let cy: CGFloat = height / 2 + 2
        let rx: CGFloat = isScore ? 128 : 134
        let ry: CGFloat = isScore ? 112 : 108

        var nodes: [Node] = []
        let count = Double(max(1, ring.count))
        for (i, key) in ring.enumerated() {
            let degrees: Double = -90 + Double(i) * 360 / count
            let angle: Double = degrees * Double.pi / 180
            let px: CGFloat = cx + rx * CGFloat(cos(angle))
            let py: CGFloat = cy + ry * CGFloat(sin(angle))
            nodes.append(Node(key: key, isCentre: false, center: CGPoint(x: px, y: py), half: CGSize(width: 36, height: 13)))
        }
        nodes.append(Node(key: centre, isCentre: true, center: CGPoint(x: cx, y: cy), half: CGSize(width: 46, height: 17)))
        let byKey = Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, $0) })

        var edges: [Edge] = []
        var seen = Set<String>()
        for connection in connections {
            guard connection.to != centre, let other = byKey[connection.to], let middle = byKey[centre] else { continue }
            let both = connection.direction == "both"
            let outward = connection.direction != "in"
            guard seen.insert("\(connection.to)|\(connection.direction)").inserted else { continue }
            let source = outward ? middle : other
            let target = outward ? other : middle
            let curved = !isScore && !both
            edges.append(edge(from: source, to: target, label: connection.label,
                              evidence: connection.evidence.isEmpty ? .moderate : SignalEvidence(raw: connection.evidence),
                              bend: curved ? 21 : 0, bothEnds: both, labelNearTarget: outward))
        }
        return SignalMapLayout(size: CGSize(width: baseWidth, height: height), nodes: nodes, edges: edges)
    }

    /// The point on a node's rectangle where a line towards `target` leaves it.
    private static func clip(_ node: Node, toward target: CGPoint, margin: CGFloat) -> CGPoint {
        let dx = target.x - node.center.x
        let dy = target.y - node.center.y
        let s = min((node.half.width + margin) / max(abs(dx), 1e-6), (node.half.height + margin) / max(abs(dy), 1e-6))
        return CGPoint(x: node.center.x + dx * s, y: node.center.y + dy * s)
    }

    private static func edge(from a: Node, to b: Node, label: String, evidence: SignalEvidence, bend: CGFloat, bothEnds: Bool,
                             labelNearTarget: Bool) -> Edge {
        let p0 = clip(a, toward: b.center, margin: 2)
        let p1 = clip(b, toward: a.center, margin: 3)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let length = max(hypot(dx, dy), 1)
        let control = CGPoint(x: (p0.x + p1.x) / 2 + dy / length * bend, y: (p0.y + p1.y) / 2 - dx / length * bend)

        // Arrowheads along the curve's tangent at each end; the line stops short of the tip it points at.
        func head(at tip: CGPoint, from other: CGPoint) -> (head: Head, stop: CGPoint) {
            let tx = tip.x - other.x
            let ty = tip.y - other.y
            let tl = max(hypot(tx, ty), 1)
            let ux = tx / tl
            let uy = ty / tl
            let along: CGFloat = 7.5
            let across: CGFloat = 3.6
            let base = CGPoint(x: tip.x - ux * along, y: tip.y - uy * along)
            let h = Head(tip: tip, left: CGPoint(x: base.x - uy * across, y: base.y + ux * across),
                         right: CGPoint(x: base.x + uy * across, y: base.y - ux * across))
            return (h, CGPoint(x: tip.x - ux * along * 0.7, y: tip.y - uy * along * 0.7))
        }
        let end = head(at: p1, from: control)
        var heads = [end.head]
        var start = p0
        if bothEnds {
            let first = head(at: p0, from: control)
            heads.append(first.head)
            start = first.stop
        }
        let t: CGFloat = bothEnds ? 0.5 : (labelNearTarget ? 0.62 : 0.38)
        let labelPoint = CGPoint(x: (1 - t) * (1 - t) * p0.x + 2 * t * (1 - t) * control.x + t * t * p1.x,
                                 y: (1 - t) * (1 - t) * p0.y + 2 * t * (1 - t) * control.y + t * t * p1.y)
        return Edge(from: a.key, to: b.key, start: start, control: control, end: end.stop, heads: heads, label: label,
                    labelPoint: labelPoint, evidence: evidence, bothEnds: bothEnds)
    }
}
