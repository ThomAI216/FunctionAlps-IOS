import Foundation

/// What a meal did to you, 2–3 hours later: energy, focus, digestion — and, when one of them went badly,
/// what exactly went badly. Pure: the sheet collects it, this type says how it lands in `nb_meal_reactions`.
///
/// Column contract (all of these already exist on the row — no migration):
/// `overall` AND `digestion` carry the digestion read, because how a meal SAT is the meal's headline and
/// everything downstream (the Food tab sentiment line, the gut dashboard's reaction factor, the
/// food×reaction engine) already reads `overall`. `energy` gets the energy read. `focus` has no column,
/// so it rides in `responses`. The symptom columns (`bloating`, `fullness`, `gas_burden`, `burning`,
/// `fatigue`) are set from the precision pills, so the gut burden keeps working from ticks alone.
struct MealFeedback: Sendable, Equatable {
    /// Five steps, stored on the 0–10 scale the row has always used. 1/3 read as rough, 5 as off,
    /// 7/9 as fine — exactly the bands `MealReaction.sentiment` already draws.
    enum Read: Int, Sendable, Hashable, CaseIterable, Identifiable {
        case rough = 1, off = 3, okay = 5, good = 7, great = 9
        var id: Int { rawValue }
        /// A read worth asking a follow-up about.
        var isPoor: Bool { rawValue <= 3 }
    }

    var energy: Read?
    var focus: Read?
    var digestion: Read?
    var energyPills: [String] = []
    var focusPills: [String] = []
    var digestionPills: [String] = []

    var hasAnswer: Bool {
        energy != nil || focus != nil || digestion != nil
            || !energyPills.isEmpty || !focusPills.isEmpty || !digestionPills.isEmpty
    }

    /// A ticked precision pill means "yes, and notably" — the moderate step on the 0–10 symptom columns.
    static let ticked = 6

    /// `overfull` is written as `heavy`: the word the Food tab lines and the engine already know.
    private static let flagAlias: [String: String] = ["overfull": "heavy"]

    var flags: [String] {
        var out: [String] = []
        if let d = digestion { if d.rawValue < 4 { out.append("overall_rough") } else if d.rawValue < 7 { out.append("overall_off") } }
        out += digestionPills.map { Self.flagAlias[$0] ?? $0 }
        out += energyPills
        out += focusPills
        return out
    }

    private func has(_ pill: String) -> Bool { digestionPills.contains(pill) }

    var bloating: Int { has("bloating") ? Self.ticked : 0 }
    var fullness: Int { has("overfull") ? Self.ticked : 0 }
    var gasBurden: Int { has("gas") ? Self.ticked : 0 }
    var burning: Int { has("reflux") ? Self.ticked : 0 }
    var fatigue: Int { energyPills.contains("energy_crash") || energyPills.contains("sleepy") ? Self.ticked : 0 }

    /// Every read that was actually given, on the 0–10 scale.
    var responses: [String: Double] {
        var out: [String: Double] = [:]
        if let d = digestion { out["digestion"] = Double(d.rawValue); out["overall"] = Double(d.rawValue) }
        if let e = energy { out["energy"] = Double(e.rawValue) }
        if let f = focus { out["focus"] = Double(f.rawValue) }
        return out
    }

    /// The headline: how the meal sat.
    var overall: Double? { digestion.map { Double($0.rawValue) } }
}

/// The words, in the app's own vocabulary — energy and focus reuse the check-in's five, so a member
/// meets the same scale everywhere.
enum MealFeedbackCopy {
    static func energyWords() -> [String] {
        [String(localized: "w.drained", defaultValue: "Drained"), String(localized: "w.low", defaultValue: "Low"),
         String(localized: "w.steady", defaultValue: "Steady"), String(localized: "w.good", defaultValue: "Good"),
         String(localized: "w.buzzing", defaultValue: "Buzzing")]
    }

    static func focusWords() -> [String] {
        [String(localized: "w.foggy", defaultValue: "Foggy"), String(localized: "w.hazy", defaultValue: "Hazy"),
         String(localized: "w.okay", defaultValue: "Okay"), String(localized: "w.clear", defaultValue: "Clear"),
         String(localized: "w.sharp", defaultValue: "Sharp")]
    }

    static func digestionWords() -> [String] {
        [String(localized: "reaction.d.rough", defaultValue: "Rough"), String(localized: "reaction.d.off", defaultValue: "Off"),
         String(localized: "reaction.d.okay", defaultValue: "Okay"), String(localized: "reaction.d.good", defaultValue: "Good"),
         String(localized: "reaction.d.satWell", defaultValue: "Sat well")]
    }

    /// What exactly was off — the gut check-in's vocabulary, so a symptom means the same thing
    /// whether it was ticked after a meal or in the evening.
    static var digestionPills: [PillOption] {
        [
            PillOption(key: "bloating", label: String(localized: "gut.pill.bloating", defaultValue: "Bloating")),
            PillOption(key: "gas", label: String(localized: "gut.pill.gas", defaultValue: "Gas")),
            PillOption(key: "reflux", label: String(localized: "gut.pill.reflux", defaultValue: "Reflux")),
            PillOption(key: "overfull", label: String(localized: "gut.pill.overfull", defaultValue: "Over-full")),
            PillOption(key: "cramping", label: String(localized: "gut.pill.cramping", defaultValue: "Cramping")),
            PillOption(key: "nausea", label: String(localized: "gut.pill.nausea", defaultValue: "Nausea")),
            PillOption(key: "loose", label: String(localized: "gut.pill.loose", defaultValue: "Loose")),
        ]
    }

    static var energyPills: [PillOption] {
        [
            PillOption(key: "energy_crash", label: String(localized: "reaction.e.crash", defaultValue: "Crashed")),
            PillOption(key: "sleepy", label: String(localized: "reaction.e.sleepy", defaultValue: "Sleepy")),
            PillOption(key: "hungry_again", label: String(localized: "reaction.e.hungry", defaultValue: "Hungry again")),
            PillOption(key: "shaky", label: String(localized: "reaction.e.shaky", defaultValue: "Shaky")),
            PillOption(key: "wired", label: String(localized: "reaction.e.wired", defaultValue: "Wired")),
        ]
    }

    static var focusPills: [PillOption] {
        [
            PillOption(key: "foggy", label: String(localized: "reaction.f.foggy", defaultValue: "Foggy")),
            PillOption(key: "restless", label: String(localized: "reaction.f.restless", defaultValue: "Couldn't settle")),
            PillOption(key: "dull", label: String(localized: "reaction.f.dull", defaultValue: "Dull")),
            PillOption(key: "scattered", label: String(localized: "reaction.f.scattered", defaultValue: "Scattered")),
        ]
    }
}
