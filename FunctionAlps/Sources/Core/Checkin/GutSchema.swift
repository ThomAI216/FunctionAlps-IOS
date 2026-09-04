import Foundation

/// The gut check-in — the Expo `gut-schema.ts` verbatim: three dimensions (comfort, stool, food
/// reactions), each a 0–100 slider with precision pills that appear only when the read is ≤ 60.
enum GutDimKey: String, Sendable, Hashable, CaseIterable, Codable {
    case comfort, stool, reactions
    static let order: [GutDimKey] = [.comfort, .stool, .reactions]
}

/// The stool card's two non-slider answers and the reactions card's read-only meal score.
struct GutSpecials: Sendable, Equatable {
    var bristol: Int? = nil          // 1–7
    var frequency: Int? = nil        // stools / 24 h, 0–15
    var reactionsScore: Int? = nil   // from today's rated meals, 0–100
}

struct GutAnswers: Sendable, Equatable {
    var sliders: [String: Double] = [:]
    var pills: [String: [String]] = [:]
    var specials = GutSpecials()
    static let empty = GutAnswers()
}

typealias GutAnswerSet = [GutDimKey: GutAnswers]

extension Dictionary where Key == GutDimKey, Value == GutAnswers {
    static var blank: GutAnswerSet { Dictionary(uniqueKeysWithValues: GutDimKey.allCases.map { ($0, GutAnswers.empty) }) }
}

struct GutPillModule: Sendable, Identifiable {
    let key: String
    let title: String
    let after: String
    let when: @Sendable (GutAnswers) -> Bool
    let options: [PillOption]
    var id: String { key }
}

struct GutDimensionSpec: Sendable, Identifiable {
    let key: GutDimKey
    let title: String
    let accentHex: UInt32
    let slider: SliderSpec
    let pills: [GutPillModule]
    var id: GutDimKey { key }
}

enum GutSchema {
    /// `bandLevel(v) === 'low' || 'mid'` → the value is answered and ≤ 60.
    static func lowOrMid(_ v: Double?) -> Bool {
        guard let v else { return false }
        return v <= 60
    }

    static var comfort: GutDimensionSpec {
        GutDimensionSpec(
            key: .comfort, title: String(localized: "gut.comfort.title", defaultValue: "Digestion comfort"), accentHex: 0x14B8A6,
            slider: SliderSpec(key: "comfort", label: String(localized: "gut.comfort.slider", defaultValue: "Comfort"),
                               lowLabel: String(localized: "gut.comfort.low", defaultValue: "Heavy/bloated"), highLabel: String(localized: "gut.comfort.high", defaultValue: "Light"),
                               words: [String(localized: "gut.comfort.w0", defaultValue: "Bloated"), String(localized: "gut.comfort.w1", defaultValue: "Heavy"), String(localized: "gut.comfort.w2", defaultValue: "Okay"), String(localized: "gut.comfort.w3", defaultValue: "Easing"), String(localized: "gut.comfort.w4", defaultValue: "Light")]),
            pills: [
                GutPillModule(key: "symptoms", title: String(localized: "gut.symptoms.title", defaultValue: "What felt off?"), after: "comfort", when: { lowOrMid($0.sliders["comfort"]) }, options: [
                    PillOption(key: "bloating", label: String(localized: "gut.pill.bloating", defaultValue: "Bloating")), PillOption(key: "gas", label: String(localized: "gut.pill.gas", defaultValue: "Gas")),
                    PillOption(key: "reflux", label: String(localized: "gut.pill.reflux", defaultValue: "Reflux")), PillOption(key: "cramping", label: String(localized: "gut.pill.cramping", defaultValue: "Cramping")),
                    PillOption(key: "nausea", label: String(localized: "gut.pill.nausea", defaultValue: "Nausea")), PillOption(key: "overfull", label: String(localized: "gut.pill.overfull", defaultValue: "Over-full")),
                    PillOption(key: "pain", label: String(localized: "gut.pill.pain", defaultValue: "Pain")),
                ]),
                GutPillModule(key: "timing", title: String(localized: "gut.timing.title", defaultValue: "When?"), after: "symptoms", when: { !($0.pills["symptoms"] ?? []).isEmpty }, options: [
                    PillOption(key: "after_meals", label: String(localized: "gut.pill.afterMeals", defaultValue: "After meals")), PillOption(key: "morning", label: String(localized: "gut.pill.morning", defaultValue: "Morning")),
                    PillOption(key: "evening", label: String(localized: "gut.pill.evening", defaultValue: "Evening")), PillOption(key: "all_day", label: String(localized: "gut.pill.allDay", defaultValue: "All day")),
                ]),
                GutPillModule(key: "trigger", title: String(localized: "gut.trigger.title", defaultValue: "Suspected trigger?"), after: "symptoms", when: { !($0.pills["symptoms"] ?? []).isEmpty }, options: [
                    PillOption(key: "dairy", label: String(localized: "gut.pill.dairy", defaultValue: "Dairy")), PillOption(key: "gluten", label: String(localized: "gut.pill.gluten", defaultValue: "Gluten")),
                    PillOption(key: "fried", label: String(localized: "gut.pill.fried", defaultValue: "Fried")), PillOption(key: "raw_veg", label: String(localized: "gut.pill.rawVeg", defaultValue: "Raw veg")),
                    PillOption(key: "coffee", label: String(localized: "gut.pill.coffee", defaultValue: "Coffee")), PillOption(key: "alcohol", label: String(localized: "gut.pill.alcohol", defaultValue: "Alcohol")),
                    PillOption(key: "none", label: String(localized: "gut.pill.none", defaultValue: "None")),
                ]),
            ])
    }

    static var stool: GutDimensionSpec {
        GutDimensionSpec(
            key: .stool, title: String(localized: "gut.stool.title", defaultValue: "Stool"), accentHex: 0xA16207,
            slider: SliderSpec(key: "ease", label: String(localized: "gut.stool.slider", defaultValue: "Ease"),
                               lowLabel: String(localized: "gut.stool.low", defaultValue: "Strained"), highLabel: String(localized: "gut.stool.high", defaultValue: "Easy & complete"),
                               words: [String(localized: "gut.stool.w0", defaultValue: "Strained"), String(localized: "gut.stool.w1", defaultValue: "Tough"), String(localized: "gut.stool.w2", defaultValue: "Okay"), String(localized: "gut.stool.w3", defaultValue: "Easy"), String(localized: "gut.stool.w4", defaultValue: "Effortless")]),
            pills: [
                GutPillModule(key: "stool_off", title: String(localized: "gut.stoolOff.title", defaultValue: "Anything off?"), after: "ease", when: { lowOrMid($0.sliders["ease"]) }, options: [
                    PillOption(key: "urgency", label: String(localized: "gut.pill.urgency", defaultValue: "Urgency")), PillOption(key: "straining", label: String(localized: "gut.pill.straining", defaultValue: "Straining")),
                    PillOption(key: "incomplete", label: String(localized: "gut.pill.incomplete", defaultValue: "Incomplete")), PillOption(key: "mucus", label: String(localized: "gut.pill.mucus", defaultValue: "Mucus")),
                    PillOption(key: "undigested", label: String(localized: "gut.pill.undigested", defaultValue: "Undigested food")),
                ]),
            ])
    }

    static var reactions: GutDimensionSpec {
        GutDimensionSpec(
            key: .reactions, title: String(localized: "gut.reactions.title", defaultValue: "Food reactions"), accentHex: 0xF59E0B,
            slider: SliderSpec(key: "reactions", label: String(localized: "gut.reactions.slider", defaultValue: "How did food sit?"),
                               lowLabel: String(localized: "gut.reactions.low", defaultValue: "Reacted a lot"), highLabel: String(localized: "gut.reactions.high", defaultValue: "All sat well"),
                               words: [String(localized: "gut.reactions.w0", defaultValue: "Reacted"), String(localized: "gut.reactions.w1", defaultValue: "Touchy"), String(localized: "gut.reactions.w2", defaultValue: "Okay"), String(localized: "gut.reactions.w3", defaultValue: "Mostly fine"), String(localized: "gut.reactions.w4", defaultValue: "All good")]),
            pills: [
                GutPillModule(key: "react_which", title: String(localized: "gut.reactWhich.title", defaultValue: "Which meal felt worst?"), after: "reactions", when: { lowOrMid($0.sliders["reactions"]) }, options: [
                    PillOption(key: "breakfast", label: String(localized: "gut.pill.breakfast", defaultValue: "Breakfast")), PillOption(key: "lunch", label: String(localized: "gut.pill.lunch", defaultValue: "Lunch")),
                    PillOption(key: "dinner", label: String(localized: "gut.pill.dinner", defaultValue: "Dinner")), PillOption(key: "snack", label: String(localized: "gut.pill.snack", defaultValue: "Snack")),
                ]),
                GutPillModule(key: "react_what", title: String(localized: "gut.reactWhat.title", defaultValue: "What reaction?"), after: "react_which", when: { !($0.pills["react_which"] ?? []).isEmpty }, options: [
                    PillOption(key: "bloating", label: String(localized: "gut.pill.bloating", defaultValue: "Bloating")), PillOption(key: "gas", label: String(localized: "gut.pill.gas", defaultValue: "Gas")),
                    PillOption(key: "loose", label: String(localized: "gut.pill.loose", defaultValue: "Loose")), PillOption(key: "cramp", label: String(localized: "gut.pill.cramp", defaultValue: "Cramp")),
                    PillOption(key: "reflux", label: String(localized: "gut.pill.reflux", defaultValue: "Reflux")), PillOption(key: "energy_crash", label: String(localized: "gut.pill.energyCrash", defaultValue: "Energy crash")),
                ]),
            ])
    }

    static var dimensions: [GutDimensionSpec] { [comfort, stool, reactions] }
    static func spec(_ key: GutDimKey) -> GutDimensionSpec {
        switch key { case .comfort: comfort; case .stool: stool; case .reactions: reactions }
    }

    static var bristolOptions: [PillOption] {
        [
            PillOption(key: "1", label: String(localized: "gut.bristol.1", defaultValue: "1 Hard lumps")), PillOption(key: "2", label: String(localized: "gut.bristol.2", defaultValue: "2 Lumpy")),
            PillOption(key: "3", label: String(localized: "gut.bristol.3", defaultValue: "3 Cracked")), PillOption(key: "4", label: String(localized: "gut.bristol.4", defaultValue: "4 Smooth")),
            PillOption(key: "5", label: String(localized: "gut.bristol.5", defaultValue: "5 Soft blobs")), PillOption(key: "6", label: String(localized: "gut.bristol.6", defaultValue: "6 Mushy")),
            PillOption(key: "7", label: String(localized: "gut.bristol.7", defaultValue: "7 Liquid")),
        ]
    }

    /// The modules that apply to these answers (`selectPills`).
    static func visiblePills(_ spec: GutDimensionSpec, _ a: GutAnswers) -> [GutPillModule] { spec.pills.filter { $0.when(a) } }
}
