import Foundation

/// The words on the "Bon appétit" moment after a meal is logged (owner, 2026-11-10: "a little library of phrases
/// for when they have pictured the meal and validated it — a transition screen, bon appétit, then back home").
/// Warm, short, never a judgement of the plate and never a health claim (CLAUDE.md rule 6). Never the same twice
/// in a row.
enum BonAppetit {
    struct Phrase: Sendable, Equatable {
        let title: String
        let line: String
    }

    static var phrases: [Phrase] {
        [
            Phrase(title: String(localized: "bonappetit.1.title", defaultValue: "Bon appétit"),
                   line: String(localized: "bonappetit.1.line", defaultValue: "Logged. Now enjoy it.")),
            Phrase(title: String(localized: "bonappetit.2.title", defaultValue: "Enjoy your meal"),
                   line: String(localized: "bonappetit.2.line", defaultValue: "Sit down, slow down, taste it.")),
            Phrase(title: String(localized: "bonappetit.3.title", defaultValue: "Savour every bite"),
                   line: String(localized: "bonappetit.3.line", defaultValue: "Slowly, and with pleasure.")),
            Phrase(title: String(localized: "bonappetit.4.title", defaultValue: "Take your time"),
                   line: String(localized: "bonappetit.4.line", defaultValue: "Put the phone down · the meal is in.")),
            Phrase(title: String(localized: "bonappetit.5.title", defaultValue: "Bon appétit"),
                   line: String(localized: "bonappetit.5.line", defaultValue: "A few slow breaths, then the first bite.")),
            Phrase(title: String(localized: "bonappetit.6.title", defaultValue: "Enjoy"),
                   line: String(localized: "bonappetit.6.line", defaultValue: "Chew slowly · enjoy the moment.")),
            Phrase(title: String(localized: "bonappetit.7.title", defaultValue: "Good food, good day"),
                   line: String(localized: "bonappetit.7.line", defaultValue: "Enjoy it, and the rest of your day.")),
            Phrase(title: String(localized: "bonappetit.8.title", defaultValue: "Time to eat"),
                   line: String(localized: "bonappetit.8.line", defaultValue: "Enjoy it with all your senses.")),
        ]
    }

    /// `UserDefaults` key holding the last phrase shown, so the next one differs.
    static let lastKey = "fa.bonappetit.last"

    /// A phrase index other than `last` (any one when `last` is nil or out of range). `roll` is a number in
    /// 0..<count-1 — the caller's dice, so the choice is testable.
    static func pick(count: Int, last: Int?, roll: Int) -> Int {
        guard count > 1 else { return 0 }
        guard let last, (0..<count).contains(last) else { return ((roll % count) + count) % count }
        let r = ((roll % (count - 1)) + (count - 1)) % (count - 1)
        return r >= last ? r + 1 : r
    }

    /// The phrase for this meal, remembering it so the next meal gets another one.
    static func next(defaults: UserDefaults = .standard) -> Phrase {
        let all = phrases
        let last = defaults.object(forKey: lastKey) as? Int
        let index = pick(count: all.count, last: last, roll: Int.random(in: 0..<1000))
        defaults.set(index, forKey: lastKey)
        return all[index]
    }

    /// How long the moment stays before the app goes home on its own (a tap goes sooner).
    static let seconds: Double = 2.2
}
