import Foundation

/// One `nb_nutrients` row: the food catalogue's dictionary (key, English name, group, unit, order, hold).
struct NutrientDefinition: Sendable, Equatable {
    let key: String
    let name: String
    let groupCode: String
    let unit: String
    let sortOrder: Int
    /// Set when the nutrient is on hold (vitamin K2): listed with its amount, never with a % of reference.
    let holdReason: String?
}

/// One `nutrient_reference_intakes_daily` row (EFSA DRV 2017 today).
struct NutrientReference: Sendable, Equatable {
    let nutrientKey: String
    let setCode: String
    /// "male" | "female" | "any".
    let sex: String
    let lifeStage: String
    /// "PRI" | "AI".
    let kind: String
    let amount: Double
    let unit: String
}

/// The dictionary and the reference intakes, read once per screen. Empty = not readable: the screens fall back to
/// the 34 legacy keys with the app's own names and show no %.
struct NutrientCatalogue: Sendable, Equatable {
    var definitions: [NutrientDefinition] = []
    var references: [NutrientReference] = []

    static let empty = NutrientCatalogue()
}

/// `resolution_meta.nutrient_metrics[key]` as `analyze-meal` writes it.
struct MealNutrientMetric: Sendable, Equatable {
    let value: Double?
    /// "complete" only when every food of the meal carried every term; anything else reads as partial.
    let status: String
    let coverage: Double?

    var isComplete: Bool { status == "complete" }
}

/// The full nutrient catalogue of a meal (or a day), grouped for display. Pure: the facts come from the stored meal
/// and the dictionary; nothing is computed here but sums, shares and the % of a reference intake.
/// Rules (shared contract): an absent key is "no data", never 0; a 0 whose data is all "below limit" is "traces";
/// a metric is shown only when the server marked it complete; a % only where a reference row exists.
enum MealNutrients {
    enum Group: String, CaseIterable, Sendable, Hashable {
        case vitamins, minerals, aminoAcids, fattyAcids, carotenoids, other
    }

    enum ValueState: Sendable, Equatable {
        case value(Double)
        case noData
        case traces
    }

    struct Row: Sendable, Equatable, Identifiable {
        let key: String
        let name: String
        let unit: String
        let state: ValueState
        /// Not every food of the meal (or not every meal of the day) carried a value: the amount is a partial sum.
        let partial: Bool
        let percentOfReference: Int?
        var id: String { key }
    }

    struct Section: Sendable, Equatable, Identifiable {
        let group: Group
        let rows: [Row]
        var id: String { group.rawValue }
        /// Rows with a value or traces (not "no data").
        var measured: Int { rows.filter { $0.state != .noData }.count }
    }

    enum MetricState: Sendable, Equatable {
        case value(Double)
        case partial
        case noData
    }

    struct Metric: Sendable, Equatable, Identifiable {
        let key: String
        let name: String
        let unit: String
        let state: MetricState
        let percentOfReference: Int?
        var id: String { key }
    }

    /// What one meal (or one day) says about each key, canonical dictionary keys throughout.
    struct Source: Sendable, Equatable {
        var totals: [String: Double] = [:]
        var traces: Set<String> = []
        var partial: Set<String> = []
    }

    /// Stored elsewhere on the meal row (kcal and the macros): never a row here.
    static let macroKeys: Set<String> = ["kcal", "energy_kcal", "energy_kj", "protein_g", "fat_g", "carbs_g", "fiber_g"]
    /// The two metrics the meal screen shows, in order.
    static let metricKeys = ["omega6_omega3_ratio", "epa_dha_mg"]
    /// Amount only, never a %: amino acids, carotenoids and vitamin K2.
    static let amountOnlyGroups: Set<String> = ["amino_acid", "carotenoid"]
    static let amountOnlyKeys: Set<String> = ["vitamin_k2_mcg"]
    /// Legacy keys that are not dictionary keys → the dictionary key whose name they carry. A legacy row is hidden
    /// when its dictionary key has a value in the same meal (EPA/DHA in g), so one nutrient is never listed twice.
    static let legacyAliases: [String: String] = [
        "omega3_g": "omega3_total_g", "omega6_g": "omega6_total_g", "epa_mg": "epa_g", "dha_mg": "dha_g",
    ]

    /// The group of each of the 34 legacy keys, used only when the dictionary could not be read.
    static let legacyGroups: [String: Group] = [
        "sugar_g": .other, "saturated_fat_g": .fattyAcids, "alcohol_g": .other,
        "omega3_g": .fattyAcids, "omega6_g": .fattyAcids, "ala_g": .fattyAcids, "epa_mg": .fattyAcids, "dha_mg": .fattyAcids,
        "vitamin_a_mcg": .vitamins, "vitamin_c_mg": .vitamins, "vitamin_d_mcg": .vitamins, "vitamin_e_mg": .vitamins,
        "vitamin_k_mcg": .vitamins, "vitamin_k2_mcg": .vitamins, "thiamin_mg": .vitamins, "riboflavin_mg": .vitamins,
        "niacin_mg": .vitamins, "b6_mg": .vitamins, "b12_mcg": .vitamins, "folate_mcg": .vitamins, "biotin_mcg": .vitamins,
        "choline_mg": .other,
        "calcium_mg": .minerals, "iron_mg": .minerals, "magnesium_mg": .minerals, "phosphorus_mg": .minerals,
        "potassium_mg": .minerals, "sodium_mg": .minerals, "zinc_mg": .minerals, "selenium_mcg": .minerals,
        "iodine_mcg": .minerals, "copper_mg": .minerals, "manganese_mg": .minerals, "chromium_mcg": .minerals,
    ]

    /// The display group of a dictionary `group_code`; nil = not a row (the omega metrics are shown as metrics).
    static func group(forCode code: String) -> Group? {
        switch code {
        case "vitamin": return .vitamins
        case "mineral": return .minerals
        case "amino_acid": return .aminoAcids
        case "fatty_acid", "fat_class": return .fattyAcids
        case "carotenoid": return .carotenoids
        case "omega_metric": return nil
        default: return .other
        }
    }

    // MARK: Keys

    /// Every key a stored map may carry: the dictionary's plus the 34 legacy keys.
    static func knownKeys(_ catalogue: NutrientCatalogue) -> [String] {
        catalogue.definitions.map(\.key) + MicroPresence.catalogueKeys
    }

    /// `convertFromSnakeCase` turns `sfa_4_0_g` into `sfa40G`, and `SnakeKeys` cannot put the underscores back
    /// (`sfa40_g`). Matching on the camel form against the known keys recovers the backend's own key.
    static func canonicalIndex(_ keys: [String]) -> [String: String] {
        var index: [String: String] = [:]
        for key in keys where index[SnakeKeys.camel(key)] == nil { index[SnakeKeys.camel(key)] = key }
        return index
    }

    static func canonical(_ key: String, in index: [String: String]) -> String {
        index[SnakeKeys.camel(key)] ?? key
    }

    private static func canonicalised<V>(_ map: [String: V], _ index: [String: String]) -> [String: V] {
        var out: [String: V] = [:]
        for (key, value) in map { out[canonical(key, in: index)] = value }
        return out
    }

    // MARK: Sources

    /// One meal: its totals, which keys are traces and which are partial sums.
    /// New meals (`by_key` present): traces = total 0 and `below_limit ≥ by_key`; partial = `by_key < 1`.
    /// Old meals: no traces (nothing recorded them), partial = the legacy `micro_coverage.partial` list.
    static func source(meal: MealLog, knownKeys: [String]) -> Source {
        let index = canonicalIndex(knownKeys)
        let totals = canonicalised(meal.micros, index)
        var source = Source(totals: totals)
        if let rawByKey = meal.microCoverage?.byKey {
            let byKey = canonicalised(rawByKey, index)
            let below = canonicalised(meal.microCoverage?.belowLimit ?? [:], index)
            for (key, total) in totals {
                let share = byKey[key] ?? 0
                if total == 0, let b = below[key], b > 0, b >= share {
                    source.traces.insert(key)
                } else if share < 1 {
                    source.partial.insert(key)
                }
            }
        } else {
            let listed = Set((meal.microCoverage?.partial ?? []).map { canonical($0, in: index) })
            source.partial = listed.intersection(totals.keys)
        }
        return source
    }

    /// A day: the analysed meals summed. Traces only when every meal carrying the key had it as traces; partial
    /// when a meal lacks the key or carried a partial sum.
    static func source(day meals: [MealLog], knownKeys: [String]) -> Source {
        let sources = meals.filter(\.isAnalysed).map { source(meal: $0, knownKeys: knownKeys) }
        var out = Source()
        let keys = Set(sources.flatMap { $0.totals.keys })
        for key in keys {
            let carrying = sources.filter { $0.totals[key] != nil }
            out.totals[key] = carrying.reduce(0) { $0 + ($1.totals[key] ?? 0) }
            if carrying.allSatisfy({ $0.traces.contains(key) }) {
                out.traces.insert(key)
            } else if carrying.count < sources.count || carrying.contains(where: { $0.partial.contains(key) }) {
                out.partial.insert(key)
            }
        }
        return out
    }

    // MARK: Sections

    private struct Entry {
        let key: String
        let group: Group
        let unit: String
        let name: String
        let order: Int
        let amountOnly: Bool
    }

    /// The unit a legacy key carries in its name (`_mcg`, `_mg`, `_g`).
    static func unit(fromKey key: String) -> String {
        if key.hasSuffix("_mcg") { return "mcg" }
        if key.hasSuffix("_mg") { return "mg" }
        if key.hasSuffix("_g") { return "g" }
        return ""
    }

    /// Grouped rows, in the contract's group order and the dictionary's sort order. Names: the translated name when
    /// `preferTranslated` (a non-English UI) and one exists, else the dictionary's, else `fallback`; a key with no
    /// name at all is left out. Without a dictionary: the 34 legacy keys, named by `fallback`.
    static func sections(
        source: Source,
        catalogue: NutrientCatalogue,
        sex: MemberProfile.Sex?,
        preferTranslated: Bool = false,
        translated: (String) -> String? = { _ in nil },
        fallback: (String) -> String? = { _ in nil }
    ) -> [Section] {
        var entries: [Entry] = []
        if catalogue.definitions.isEmpty {
            for (i, key) in MicroPresence.catalogueKeys.enumerated() {
                guard let group = legacyGroups[key], let name = (preferTranslated ? translated(key) : nil) ?? fallback(key) else { continue }
                entries.append(Entry(key: key, group: group, unit: unit(fromKey: key), name: name, order: i, amountOnly: amountOnlyKeys.contains(key)))
            }
        } else {
            var definitions: [String: NutrientDefinition] = [:]
            for d in catalogue.definitions where definitions[d.key] == nil { definitions[d.key] = d }
            for d in catalogue.definitions where !macroKeys.contains(d.key) {
                guard definitions[d.key] == d, let group = Self.group(forCode: d.groupCode) else { continue }
                let name = (preferTranslated ? translated(d.key) : nil) ?? (d.name.isEmpty ? fallback(d.key) : d.name)
                guard let name else { continue }
                let amountOnly = amountOnlyGroups.contains(d.groupCode) || amountOnlyKeys.contains(d.key) || d.holdReason != nil
                entries.append(Entry(key: d.key, group: group, unit: d.unit, name: name, order: d.sortOrder, amountOnly: amountOnly))
            }
            for (i, alias) in legacyAliases.sorted(by: { $0.key < $1.key }).enumerated() {
                let legacy = alias.key, target = alias.value
                guard definitions[legacy] == nil, source.totals[legacy] != nil, source.totals[target] == nil else { continue }
                guard let name = (preferTranslated ? translated(legacy) : nil) ?? definitions[target]?.name ?? fallback(legacy) else { continue }
                entries.append(Entry(key: legacy, group: .fattyAcids, unit: unit(fromKey: legacy), name: name, order: Int.max - legacyAliases.count + i, amountOnly: false))
            }
        }
        return Group.allCases.compactMap { group in
            let rows = entries.filter { $0.group == group }.sorted { $0.order < $1.order }.map { row($0, source: source, catalogue: catalogue, sex: sex) }
            return rows.isEmpty ? nil : Section(group: group, rows: rows)
        }
    }

    private static func row(_ e: Entry, source: Source, catalogue: NutrientCatalogue, sex: MemberProfile.Sex?) -> Row {
        let state: ValueState
        if let total = source.totals[e.key] {
            state = source.traces.contains(e.key) ? .traces : .value(total)
        } else {
            state = .noData
        }
        var partial = false
        var percent: Int?
        if case .value(let v) = state {
            partial = source.partial.contains(e.key)
            if !e.amountOnly { percent = percentOfReference(v, key: e.key, unit: e.unit, sex: sex, references: catalogue.references) }
        }
        return Row(key: e.key, name: e.name, unit: e.unit, state: state, partial: partial, percentOfReference: percent)
    }

    // MARK: Metrics

    /// Omega-6 : omega-3 and EPA + DHA. A value only when the server marked the metric complete; otherwise
    /// "partial"; absent = no data. A meal analysed before metrics existed shows none.
    static func metrics(
        meal: MealLog,
        catalogue: NutrientCatalogue,
        sex: MemberProfile.Sex?,
        preferTranslated: Bool = false,
        translated: (String) -> String? = { _ in nil },
        fallback: (String) -> String? = { _ in nil }
    ) -> [Metric] {
        guard let stored = meal.nutrientMetrics else { return [] }
        let byKey = canonicalised(stored, canonicalIndex(metricKeys))
        return metricKeys.compactMap { key in
            let d = catalogue.definitions.first { $0.key == key }
            guard let name = (preferTranslated ? translated(key) : nil) ?? d?.name ?? fallback(key) else { return nil }
            let unit = d?.unit ?? (key.hasSuffix("_mg") ? "mg" : "ratio")
            let state: MetricState
            if let m = byKey[key] {
                if m.isComplete { state = m.value.map { MetricState.value($0) } ?? .noData } else { state = .partial }
            } else {
                state = .noData
            }
            var percent: Int?
            if case .value(let v) = state { percent = percentOfReference(v, key: key, unit: unit, sex: sex, references: catalogue.references) }
            return Metric(key: key, name: name, unit: unit, state: state, percentOfReference: percent)
        }
    }

    // MARK: Reference intakes

    /// The adult row for the member's sex (else the "any" row), PRI before AI. Unknown sex: the "any" row only —
    /// no sex is assumed. Nil when no row fits.
    static func reference(for key: String, sex: MemberProfile.Sex?, in references: [NutrientReference]) -> NutrientReference? {
        let adult = references.filter { $0.nutrientKey == key && $0.lifeStage == "adult" }
        let code: String?
        if sex == .male { code = "male" } else if sex == .female { code = "female" } else { code = nil }
        let sexed = code.map { c in adult.filter { $0.sex == c } } ?? []
        let pool = sexed.isEmpty ? adult.filter { $0.sex == "any" } : sexed
        func rank(_ r: NutrientReference) -> Int { r.kind == "PRI" ? 0 : r.kind == "AI" ? 1 : 2 }
        return pool.min { (rank($0), $0.setCode) < (rank($1), $1.setCode) }
    }

    /// Mass units convert (g · mg · mcg); any other unit must match exactly. Nil = not comparable.
    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        let f = from.lowercased(), t = to.lowercased()
        if f == t { return amount }
        let inMg: [String: Double] = ["g": 1000, "mg": 1, "mcg": 0.001, "ug": 0.001, "µg": 0.001, "μg": 0.001]
        guard let a = inMg[f], let b = inMg[t] else { return nil }
        return amount * a / b
    }

    static func percentOfReference(_ value: Double, key: String, unit: String, sex: MemberProfile.Sex?, references: [NutrientReference]) -> Int? {
        guard let ref = reference(for: key, sex: sex, in: references), let target = convert(ref.amount, from: ref.unit, to: unit), target > 0 else { return nil }
        return Int((value / target * 100).rounded())
    }
}
