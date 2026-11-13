import Foundation

/// What one supplement's page may show, decided in one pure place and tested. A block whose data the server does
/// not send yet (what it does in the body, composition, price, image, learn more) is absent — never a placeholder —
/// and a part the practice does not share (`client_share`) stays out even when the server sent it.
enum SupplementPageBlocks {
    static func trimmed(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// Only an https link leaves the app.
    static func web(_ raw: String?) -> URL? {
        guard let raw = trimmed(raw), let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// "Why it's in your plan".
    static func why(_ s: Supplement) -> String? { trimmed(s.why) }

    struct BodyEffect: Equatable {
        var text: String?
        var areas: [String]
    }

    /// "What it does in your body": the sentence and its chips; nil when the server sent neither.
    static func bodyEffect(_ s: Supplement) -> BodyEffect? {
        let text = trimmed(s.whatItDoes)
        let areas = (s.bodyAreas ?? []).compactMap { trimmed($0) }
        return text == nil && areas.isEmpty ? nil : BodyEffect(text: text, areas: areas)
    }

    static func howToTake(_ s: Supplement) -> [String] { (s.howToTake ?? []).compactMap { trimmed($0) } }

    /// What the brand card shows — each part only when the practice shares it AND the server sent it.
    struct Brand: Equatable {
        var label: String?
        var pack: String?
        var price: String?
        var composition: String?
        var imageURL: URL?
        var buyURL: URL?
        var checked: Date?
        var learnMoreURL: URL?
        var isEmpty: Bool { label == nil && pack == nil && price == nil && composition == nil && imageURL == nil && buyURL == nil && learnMoreURL == nil }
    }

    static func brand(_ s: Supplement) -> Brand? {
        let share = s.clientShare
        var b = Brand()
        if share.brand {
            b.label = trimmed(s.brandLabel)
            b.pack = trimmed(s.packText)
            b.imageURL = web(s.imageUrl)
            b.buyURL = web(s.productUrl)
            b.checked = b.buyURL == nil ? nil : s.linkCheckedAt
        }
        if share.price { b.price = trimmed(s.priceText) }
        if share.composition { b.composition = trimmed(s.composition) }
        if share.learnMore { b.learnMoreURL = web(s.learnMoreUrl) }
        return b.isEmpty ? nil : b
    }

    struct Prescribed: Equatable {
        var name: String?
        var since: Date?
    }

    /// "Prescribed": who and since when.
    static func prescribed(_ s: Supplement) -> Prescribed? {
        let name = trimmed(s.prescriberName)
        let since = s.since.flatMap(ISO8601.parse)
        return name == nil && since == nil ? nil : Prescribed(name: name, since: since)
    }
}
