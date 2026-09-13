import Foundation

/// Protocol Lens — a member's logged foods checked against their active therapeutic elimination protocol(s)
/// (low-FODMAP / low-oxalate / low-salicylate), deterministically, with no model involved: the Expo
/// `lib/health/protocol-foods.ts` line for line. Three locked decisions: the clinician's per-protocol
/// VISIBILITY dial (`silent` / `soft` / `coached`) decides whether the member ever sees anything; the word
/// lists live in code with a small per-member override table; STRICTNESS is a render-time threshold on
/// always-complete matches. Never a red mark at the moment of capture — the register is "worth reviewing
/// together", and the education sheet only opens when the member taps it.
enum ProtocolLens {
    enum Severity: String, Sendable, Codable, Equatable { case high, moderate }
    enum Strictness: String, Sendable, Equatable { case strict, relaxed }
    enum Visibility: String, Sendable, Equatable, Comparable {
        case silent, soft, coached
        private var rank: Int { switch self { case .silent: 0; case .soft: 1; case .coached: 2 } }
        static func < (a: Visibility, b: Visibility) -> Bool { a.rank < b.rank }
    }

    struct PatientProtocol: Sendable, Equatable {
        let protocolKey: String       // unknown keys are skipped (forward-compatible)
        let strictness: Strictness
        let visibility: Visibility
    }

    struct Override: Sendable, Equatable {
        enum Action: String, Sendable { case allow, flag }
        let protocolKey: String
        let foodTerm: String
        let action: Action
        var severity: Severity? = nil   // `flag` only; defaults high
    }

    /// One match — the shape `nb_meal_logs.protocol_flags` stores (`item`, `protocol`, `severity`, `matched_term`).
    struct Flag: Sendable, Equatable, Codable, Identifiable {
        let item: String
        let protocolKey: String
        let severity: Severity
        let matchedTerm: String
        var id: String { "\(item)|\(protocolKey)|\(matchedTerm)" }
        /// The stored key is `protocol`; the decoder has already turned `matched_term` into `matchedTerm`.
        enum CodingKeys: String, CodingKey { case item, protocolKey = "protocol", severity, matchedTerm }
        init(item: String, protocolKey: String, severity: Severity, matchedTerm: String) {
            self.item = item; self.protocolKey = protocolKey; self.severity = severity; self.matchedTerm = matchedTerm
        }
    }

    // MARK: Education copy (the coached "Curious why?" sheet — curious teacher, never prescriptive)

    static func label(for key: String) -> String? {
        switch key {
        case "low_fodmap": String(localized: "protocol.lowFodmap.label", defaultValue: "Low-FODMAP protocol")
        case "low_oxalate": String(localized: "protocol.lowOxalate.label", defaultValue: "Low-oxalate protocol")
        case "low_salicylate": String(localized: "protocol.lowSalicylate.label", defaultValue: "Low-salicylate protocol")
        default: nil
        }
    }

    static func why(for key: String) -> String? {
        switch key {
        case "low_fodmap": String(localized: "protocol.lowFodmap.why", defaultValue: "FODMAPs are short-chain carbohydrates (like the fructans in onion and garlic) that some guts ferment quickly, which can mean gas, bloating or discomfort. Your protocol temporarily lowers them so we can learn which ones matter for you.")
        case "low_oxalate": String(localized: "protocol.lowOxalate.why", defaultValue: "Oxalates are natural plant compounds (high in spinach, beets, almonds) that can bind minerals and, for some people, contribute to kidney stones or irritation. Your protocol keeps them low while we watch how you respond.")
        case "low_salicylate": String(localized: "protocol.lowSalicylate.why", defaultValue: "Salicylates are natural aspirin-like compounds in many fruits, spices and mints. Some people are sensitive to them. Your protocol lowers them for a while so we can see what changes for you.")
        default: nil
        }
    }

    // MARK: Severity-tiered term lists (Monash-style FODMAP references + standard oxalate / salicylate tables)
    // Lowercase, matched at WORD STARTS (prefix-open, so 'cherr' catches cherry/cherries; '\btea' never hits "steak").

    private static let terms: [String: (high: [String], moderate: [String])] = [
        "low_fodmap": (
            high: ["onion", "garlic", "shallot", "leek", "wheat bread", "wheat pasta", "rye",
                   "apple", "pear", "mango", "watermelon", "cherr", "nectarine", "peach", "plum",
                   "apricot", "blackberr", "honey", "agave", "high fructose",
                   "milk", "ice cream", "soft cheese", "ricotta", "cottage cheese", "yogurt",
                   "cashew", "pistachio", "kidney bean", "baked bean", "black bean", "chickpea",
                   "hummus", "lentil", "soy milk", "silken tofu", "cauliflower", "mushroom",
                   "asparagus", "artichoke", "snow pea", "sugar snap",
                   "inulin", "chicory", "sorbitol", "mannitol", "xylitol"],
            moderate: ["avocado", "sweet potato", "broccoli", "brussels sprout", "cabbage", "celery",
                       "sweetcorn", "corn tortilla", "beetroot", "pomegranate", "grapefruit", "dried fruit",
                       "raisin", "date", "fig", "coconut milk", "almond", "almond milk", "oat milk", "sourdough",
                       "green pea", "fennel", "okra", "plantain", "banana"]
        ),
        "low_oxalate": (
            high: ["spinach", "beet", "beetroot", "rhubarb", "swiss chard", "chard", "almond",
                   "almond milk", "almond butter", "cashew", "peanut", "sesame", "tahini",
                   "potato skin", "sweet potato", "okra", "star fruit", "buckwheat",
                   "wheat bran", "oat bran", "quinoa", "cocoa", "chocolate", "dark chocolate", "soy flour",
                   "black tea"],
            moderate: ["potato", "carrot", "celery", "parsnip", "olives", "kiwi", "orange", "fig",
                       "raspberr", "blackberr", "brown rice", "oatmeal", "oats", "lentil",
                       "tomato sauce", "walnut", "pecan", "hazelnut", "green bean", "leek"]
        ),
        "low_salicylate": (
            high: ["berries", "strawberr", "raspberr", "blueberr", "blackberr", "cranberr",
                   "raisin", "currant", "dried fruit", "apricot", "orange", "mandarin",
                   "pineapple", "grapes", "tomato", "tomato sauce", "ketchup",
                   "curry", "paprika", "cayenne", "chili", "turmeric", "cumin", "oregano",
                   "thyme", "rosemary", "mint", "peppermint", "licorice", "honey",
                   "almond", "wine", "cider", "vinegar", "olive oil", "coconut oil", "tea"],
            moderate: ["apple", "avocado", "cherr", "grapefruit", "kiwi", "lemon", "lime",
                       "mango", "melon", "nectarine", "peach", "plum", "watermelon", "cucumber",
                       "zucchini", "courgette", "sweet potato", "spinach", "mushroom", "radish",
                       "walnut", "pistachio", "macadamia", "coffee"]
        ),
    ]

    static func isKnown(_ key: String) -> Bool { terms[key] != nil }

    private static func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `\bterm` — a word-start prefix match, like the web's regex.
    static func wordStart(_ name: String, _ term: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: term)) else { return false }
        return re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// All matches, all severities — strictness is NOT applied here (see `isFlagged`). Overrides run last:
    /// `allow` drops matches on that term, `flag` adds one. Most-specific-term-wins: a term that is a substring
    /// of another matched term on the same item is dropped ('potato' shadowed by 'sweet potato').
    static func match(items: [String], protocols: [PatientProtocol], overrides: [Override] = []) -> [Flag] {
        var flags: [Flag] = []
        for p in protocols {
            guard let lists = terms[p.protocolKey] else { continue }
            let allow = Set(overrides.filter { $0.protocolKey == p.protocolKey && $0.action == .allow }.map { norm($0.foodTerm) })
            let extra = overrides.filter { $0.protocolKey == p.protocolKey && $0.action == .flag }
            for item in items {
                let name = norm(item)
                if name.isEmpty { continue }
                var seen = Set<String>()
                var candidates: [(term: String, severity: Severity)] = []
                func collect(_ term: String, _ severity: Severity) {
                    guard !seen.contains(term) else { return }
                    seen.insert(term)
                    candidates.append((term, severity))
                }
                for t in lists.high where wordStart(name, t) { collect(t, .high) }
                for t in lists.moderate where wordStart(name, t) { collect(t, .moderate) }
                for o in extra {
                    let t = norm(o.foodTerm)
                    if !t.isEmpty, wordStart(name, t) { collect(t, o.severity ?? .high) }
                }
                let shadowed = Set(candidates.filter { a in candidates.contains { b in b.term != a.term && b.term.contains(a.term) } }.map(\.term))
                for c in candidates where !shadowed.contains(c.term) && !allow.contains(c.term) {
                    flags.append(Flag(item: item, protocolKey: p.protocolKey, severity: c.severity, matchedTerm: c.term))
                }
            }
        }
        return flags
    }

    /// The single strictness threshold every surface uses: strict counts everything, relaxed only high.
    static func isFlagged(_ flag: Flag, strictness: Strictness) -> Bool {
        strictness == .strict ? true : flag.severity == .high
    }

    /// One rendering mode for the app when several protocols are active: the most engaged dial wins.
    static func effectiveVisibility(_ protocols: [PatientProtocol]) -> Visibility {
        protocols.map(\.visibility).max() ?? .silent
    }

    /// The dial belongs to the PROTOCOL: a flag matched only by a silent protocol never surfaces just because
    /// another one is coached. Unknown key → silent, the fail-closed default.
    static func visibility(of protocolKey: String, in protocols: [PatientProtocol]) -> Visibility {
        protocols.first { $0.protocolKey == protocolKey }?.visibility ?? .silent
    }

    /// The strictness the member's protocols imply as a whole (any strict → strict).
    static func strictness(of protocols: [PatientProtocol]) -> Strictness {
        protocols.contains { $0.strictness == .strict } ? .strict : .relaxed
    }

    // MARK: The weekly review — wins first

    struct Week: Sendable, Equatable {
        struct Food: Sendable, Equatable, Identifiable {
            let name: String
            let count: Int
            let protocols: [String]
            var id: String { name }
        }
        let totalMeals: Int
        let fitMeals: Int
        let flaggedFoods: [Food]
    }

    /// `protocolFlags == nil` rows (legacy / never computed) are excluded from the denominator; `[]` rows count
    /// as a fit meal. Foods are counted by the MEALS containing them, not by raw flag rows.
    static func summarizeWeek(_ rows: [[Flag]?], strictness: Strictness) -> Week {
        var total = 0, fit = 0
        var foods: [String: (count: Int, protocols: Set<String>)] = [:]
        var order: [String] = []
        for row in rows {
            guard let flags = row else { continue }
            total += 1
            let passing = flags.filter { isFlagged($0, strictness: strictness) }
            if passing.isEmpty { fit += 1; continue }
            var perMeal = Set<String>()
            for f in passing {
                var entry = foods[f.matchedTerm] ?? (0, [])
                if !perMeal.contains(f.matchedTerm) { entry.count += 1; perMeal.insert(f.matchedTerm) }
                entry.protocols.insert(f.protocolKey)
                if foods[f.matchedTerm] == nil { order.append(f.matchedTerm) }
                foods[f.matchedTerm] = entry
            }
        }
        let list = order.map { Week.Food(name: $0, count: foods[$0]!.count, protocols: foods[$0]!.protocols.sorted()) }
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.name < b.name }
        return Week(totalMeals: total, fitMeals: fit, flaggedFoods: list)
    }
}
