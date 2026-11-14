import Foundation
import Testing
@testable import FunctionAlps

/// The meal's full nutrient catalogue: value / no data / traces, grouping, metrics, % of reference, old meals.
@Suite("Meal nutrients — full catalogue")
struct MealNutrientsTests {
    private static func def(_ key: String, _ group: String, _ unit: String, _ order: Int, hold: String? = nil) -> NutrientDefinition {
        NutrientDefinition(key: key, name: "Name of \(key)", groupCode: group, unit: unit, sortOrder: order, holdReason: hold)
    }

    private static func ref(_ key: String, _ sex: String, _ kind: String, _ amount: Double, _ unit: String, lifeStage: String = "adult") -> NutrientReference {
        NutrientReference(nutrientKey: key, setCode: "efsa_drv_2017", sex: sex, lifeStage: lifeStage, kind: kind, amount: amount, unit: unit)
    }

    private static let dictionary: [NutrientDefinition] = [
        def("protein_g", "energy_macro", "g", 4), def("water_g", "energy_macro", "g", 3),
        def("fiber_g", "fibre", "g", 8), def("sugar_g", "carbohydrate", "g", 11),
        def("saturated_fat_g", "fat_class", "g", 21), def("sfa_4_0_g", "fatty_acid", "g", 27),
        def("epa_g", "fatty_acid", "g", 51), def("dha_g", "fatty_acid", "g", 53),
        def("vitamin_d_mcg", "vitamin", "mcg", 58), def("vitamin_k2_mcg", "vitamin", "mcg", 70, hold: "on hold"),
        def("vitamin_c_mg", "vitamin", "mg", 72),
        def("iron_mg", "mineral", "mg", 85), def("magnesium_mg", "mineral", "mg", 86), def("selenium_mcg", "mineral", "mcg", 93),
        def("leucine_g", "amino_acid", "g", 106), def("lycopene_mcg", "carotenoid", "mcg", 126), def("caffeine_mg", "other", "mg", 132),
        def("omega3_total_g", "omega_metric", "g", 135), def("omega6_omega3_ratio", "omega_metric", "ratio", 137),
        def("epa_dha_mg", "omega_metric", "mg", 138),
    ]

    private static func catalogue(_ refs: [NutrientReference] = []) -> NutrientCatalogue {
        NutrientCatalogue(definitions: dictionary, references: refs)
    }

    private static func meal(
        _ micros: [String: Double], coverage: MealMicroCoverage? = nil, metrics: [String: MealNutrientMetric]? = nil,
        status: MealLog.AnalysisStatus = .complete
    ) -> MealLog {
        MealLog(id: UUID().uuidString, loggedAt: Date(), analysisStatus: status, micros: micros, microCoverage: coverage, nutrientMetrics: metrics)
    }

    private static func coverage(byKey: [String: Double], belowLimit: [String: Double] = [:], partial: [String] = []) -> MealMicroCoverage {
        MealMicroCoverage(tracked: 34, measured: 10, items: 2, itemsFromCatalogue: 2, partial: partial, byKey: byKey, belowLimit: belowLimit, catalogueTracked: 120, catalogueMeasured: 40)
    }

    private static func rows(_ meal: MealLog, _ catalogue: NutrientCatalogue = MealNutrientsTests.catalogue(), sex: MemberProfile.Sex? = nil) -> [String: MealNutrients.Row] {
        let source = MealNutrients.source(meal: meal, knownKeys: MealNutrients.knownKeys(catalogue))
        let all = MealNutrients.sections(source: source, catalogue: catalogue, sex: sex).flatMap(\.rows)
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Value state

    @Test("An absent key is No data, never zero; a present key is its value")
    func absentIsNoData() {
        let rows = Self.rows(Self.meal(["vitamin_c_mg": 12], coverage: Self.coverage(byKey: ["vitamin_c_mg": 1])))
        #expect(rows["vitamin_c_mg"]?.state == .value(12))
        #expect(rows["iron_mg"]?.state == .noData)
        #expect(rows["iron_mg"]?.percentOfReference == nil)
    }

    @Test("A zero whose data is all below the limit is Traces; a measured zero stays a value")
    func tracesRule() {
        let meal = Self.meal(
            ["selenium_mcg": 0, "iron_mg": 0, "magnesium_mg": 0],
            coverage: Self.coverage(byKey: ["selenium_mcg": 0.6, "iron_mg": 1, "magnesium_mg": 1], belowLimit: ["selenium_mcg": 0.6, "magnesium_mg": 0.4])
        )
        let rows = Self.rows(meal)
        #expect(rows["selenium_mcg"]?.state == .traces)
        #expect(rows["iron_mg"]?.state == .value(0))
        // Some foods were below the limit, but others measured a real zero: not traces.
        #expect(rows["magnesium_mg"]?.state == .value(0))
    }

    @Test("A key carried by part of the meal's weight is a partial sum")
    func partialShare() {
        let rows = Self.rows(Self.meal(["vitamin_c_mg": 12, "iron_mg": 2], coverage: Self.coverage(byKey: ["vitamin_c_mg": 0.75, "iron_mg": 1])))
        #expect(rows["vitamin_c_mg"]?.partial == true)
        #expect(rows["iron_mg"]?.partial == false)
    }

    // MARK: Grouping

    @Test("Groups follow the contract: order, fat classes and legacy omega keys under fatty acids, macros and metrics left out")
    func grouping() {
        let meal = Self.meal(["omega3_g": 1.2, "epa_mg": 300, "epa_g": 0.3, "dha_mg": 200, "protein_g": 30, "water_g": 100])
        let catalogue = Self.catalogue()
        let source = MealNutrients.source(meal: meal, knownKeys: MealNutrients.knownKeys(catalogue))
        let sections = MealNutrients.sections(source: source, catalogue: catalogue, sex: nil)
        #expect(sections.map(\.group) == [.vitamins, .minerals, .aminoAcids, .fattyAcids, .carotenoids, .other])
        let byGroup = Dictionary(sections.map { ($0.group, $0.rows.map(\.key)) }, uniquingKeysWith: { a, _ in a })
        #expect(byGroup[.vitamins] == ["vitamin_d_mcg", "vitamin_k2_mcg", "vitamin_c_mg"])
        #expect(byGroup[.minerals] == ["iron_mg", "magnesium_mg", "selenium_mcg"])
        // epa_mg is hidden because epa_g carries EPA in this meal; dha_mg stays (no dha_g); omega3_g borrows its name.
        #expect(byGroup[.fattyAcids] == ["saturated_fat_g", "sfa_4_0_g", "epa_g", "dha_g", "dha_mg", "omega3_g"])
        #expect(byGroup[.other] == ["water_g", "sugar_g", "caffeine_mg"])
        let all = sections.flatMap(\.rows)
        #expect(!all.contains { $0.key == "protein_g" || $0.key == "fiber_g" || $0.key == "omega6_omega3_ratio" || $0.key == "epa_mg" })
        #expect(all.first { $0.key == "omega3_g" }?.name == "Name of omega3_total_g")
        #expect(all.first { $0.key == "dha_mg" }?.unit == "mg")
    }

    @Test("A key mangled by the snake-case decoder (sfa40_g) still lands on its dictionary key")
    func mangledKeys() {
        let rows = Self.rows(Self.meal(["sfa40_g": 0.2], coverage: Self.coverage(byKey: ["sfa40_g": 1])))
        #expect(rows["sfa_4_0_g"]?.state == .value(0.2))
        #expect(rows["sfa_4_0_g"]?.partial == false)
        #expect(SnakeKeys.camel("sfa_4_0_g") == "sfa40G")
        #expect(SnakeKeys.camel("vitamin_b12_mcg") == "vitaminB12Mcg")
        #expect(SnakeKeys.camel(SnakeKeys.snake("mufa181G")) == SnakeKeys.camel("mufa_18_1_g"))
    }

    @Test("Names: the translated name when the UI prefers it, else the dictionary's")
    func names() {
        let source = MealNutrients.Source(totals: ["vitamin_c_mg": 1])
        let fr = MealNutrients.sections(source: source, catalogue: Self.catalogue(), sex: nil, preferTranslated: true, translated: { $0 == "vitamin_c_mg" ? "Vitamine C" : nil })
        let en = MealNutrients.sections(source: source, catalogue: Self.catalogue(), sex: nil, preferTranslated: false, translated: { $0 == "vitamin_c_mg" ? "Vitamine C" : nil })
        #expect(fr.flatMap(\.rows).first { $0.key == "vitamin_c_mg" }?.name == "Vitamine C")
        #expect(fr.flatMap(\.rows).first { $0.key == "iron_mg" }?.name == "Name of iron_mg")
        #expect(en.flatMap(\.rows).first { $0.key == "vitamin_c_mg" }?.name == "Name of vitamin_c_mg")
    }

    // MARK: Metrics

    @Test("A metric shows its value only when complete; otherwise Partial; absent is No data")
    func metrics() {
        let meal = Self.meal([:], metrics: [
            "omega6_omega3_ratio": MealNutrientMetric(value: 4.2, status: "complete", coverage: 1),
            "epa_dha_mg": MealNutrientMetric(value: 180, status: "partial", coverage: 0.6),
        ])
        let metrics = MealNutrients.metrics(meal: meal, catalogue: Self.catalogue(), sex: nil)
        #expect(metrics.map(\.key) == ["omega6_omega3_ratio", "epa_dha_mg"])
        #expect(metrics[0].state == .value(4.2))
        #expect(metrics[1].state == .partial)
        #expect(metrics[1].percentOfReference == nil)

        let missing = MealNutrients.metrics(meal: Self.meal([:], metrics: [:]), catalogue: Self.catalogue(), sex: nil)
        #expect(missing.map(\.state) == [.noData, .noData])
    }

    @Test("The function leaves the ratio out when a food lacks omega-3: with omega totals stored, the ratio is Partial, not No data")
    func ratioLeftOutIsPartial() {
        // Real shape (6 of 10 recent meals, 2026-11-14): omega totals present, no omega6_omega3_ratio key.
        let meal = Self.meal([:], metrics: [
            "omega3_total_g": MealNutrientMetric(value: 0.4, status: "partial", coverage: 0.7),
            "omega6_total_g": MealNutrientMetric(value: 2.6, status: "partial", coverage: 0.8),
            "epa_dha_mg": MealNutrientMetric(value: 30, status: "partial", coverage: 0.7),
        ])
        let metrics = MealNutrients.metrics(meal: meal, catalogue: Self.catalogue(), sex: nil)
        #expect(metrics.map(\.state) == [.partial, .partial])
    }

    @Test("A complete EPA + DHA gets a % of its reference; a meal from before metrics shows none")
    func metricPercent() {
        let meal = Self.meal([:], metrics: ["epa_dha_mg": MealNutrientMetric(value: 125, status: "complete", coverage: 1)])
        let metrics = MealNutrients.metrics(meal: meal, catalogue: Self.catalogue([Self.ref("epa_dha_mg", "any", "AI", 250, "mg")]), sex: .female)
        #expect(metrics.first { $0.key == "epa_dha_mg" }?.percentOfReference == 50)
        #expect(MealNutrients.metrics(meal: Self.meal(["vitamin_c_mg": 1]), catalogue: Self.catalogue(), sex: nil).isEmpty)
    }

    // MARK: % of reference

    @Test("% only where a reference row exists: sex, any, PRI before AI, adult only")
    func referencePercent() {
        let refs = [
            Self.ref("vitamin_c_mg", "female", "PRI", 95, "mg"), Self.ref("vitamin_c_mg", "male", "PRI", 110, "mg"),
            Self.ref("vitamin_c_mg", "female", "AI", 200, "mg"),
            Self.ref("vitamin_c_mg", "female", "PRI", 1000, "mg", lifeStage: "adult_premenopausal"),
            Self.ref("iron_mg", "male", "PRI", 11, "mg"),
            Self.ref("selenium_mcg", "any", "AI", 70, "mcg"),
        ]
        let catalogue = Self.catalogue(refs)
        let coverage = Self.coverage(byKey: ["vitamin_c_mg": 1, "iron_mg": 1, "selenium_mcg": 1])
        #expect(Self.rows(Self.meal(["vitamin_c_mg": 47.5], coverage: coverage), catalogue, sex: .female)["vitamin_c_mg"]?.percentOfReference == 50)
        #expect(Self.rows(Self.meal(["vitamin_c_mg": 55], coverage: coverage), catalogue, sex: .male)["vitamin_c_mg"]?.percentOfReference == 50)
        // No female iron row and no "any" row: amount only.
        #expect(Self.rows(Self.meal(["iron_mg": 5], coverage: coverage), catalogue, sex: .female)["iron_mg"]?.percentOfReference == nil)
        // Unknown sex: no sex is assumed — only an "any" row counts.
        #expect(Self.rows(Self.meal(["vitamin_c_mg": 47.5], coverage: coverage), catalogue, sex: nil)["vitamin_c_mg"]?.percentOfReference == nil)
        #expect(Self.rows(Self.meal(["selenium_mcg": 35], coverage: coverage), catalogue, sex: nil)["selenium_mcg"]?.percentOfReference == 50)
    }

    @Test("Units convert between g, mg and mcg; a unit that does not compare gives no %")
    func referenceUnits() {
        let catalogue = Self.catalogue([Self.ref("vitamin_d_mcg", "any", "AI", 0.015, "mg"), Self.ref("caffeine_mg", "any", "AI", 400, "kcal")])
        let rows = Self.rows(Self.meal(["vitamin_d_mcg": 7.5, "caffeine_mg": 80]), catalogue, sex: .male)
        #expect(rows["vitamin_d_mcg"]?.percentOfReference == 50)
        #expect(rows["caffeine_mg"]?.percentOfReference == nil)
        #expect(abs((MealNutrients.convert(1, from: "g", to: "mcg") ?? 0) - 1_000_000) < 0.001)
        #expect(MealNutrients.convert(1, from: "kcal", to: "kj") == nil)
    }

    @Test("Amino acids, carotenoids and vitamin K2 show the amount only, even with a reference row; traces never get a %")
    func amountOnly() {
        let catalogue = Self.catalogue([
            Self.ref("leucine_g", "any", "AI", 2, "g"), Self.ref("lycopene_mcg", "any", "AI", 100, "mcg"),
            Self.ref("vitamin_k2_mcg", "any", "AI", 70, "mcg"), Self.ref("selenium_mcg", "any", "AI", 70, "mcg"),
        ])
        let meal = Self.meal(
            ["leucine_g": 1, "lycopene_mcg": 50, "vitamin_k2_mcg": 35, "selenium_mcg": 0],
            coverage: Self.coverage(byKey: ["leucine_g": 1, "lycopene_mcg": 1, "vitamin_k2_mcg": 1, "selenium_mcg": 1], belowLimit: ["selenium_mcg": 1])
        )
        let rows = Self.rows(meal, catalogue, sex: .female)
        #expect(rows["leucine_g"]?.state == .value(1))
        #expect(rows["leucine_g"]?.percentOfReference == nil)
        #expect(rows["lycopene_mcg"]?.percentOfReference == nil)
        #expect(rows["vitamin_k2_mcg"]?.percentOfReference == nil)
        #expect(rows["selenium_mcg"]?.state == .traces)
        #expect(rows["selenium_mcg"]?.percentOfReference == nil)
    }

    // MARK: Old meals and no dictionary

    @Test("An old meal (34 keys, no by_key) renders: values, the legacy partial list, no traces")
    func oldMeal() {
        let old = MealMicroCoverage(tracked: 34, measured: 3, items: 2, itemsFromCatalogue: 2, partial: ["iron_mg"])
        let rows = Self.rows(Self.meal(["vitamin_c_mg": 12, "iron_mg": 2, "selenium_mcg": 0], coverage: old))
        #expect(rows["vitamin_c_mg"]?.state == .value(12))
        #expect(rows["vitamin_c_mg"]?.partial == false)
        #expect(rows["iron_mg"]?.partial == true)
        #expect(rows["selenium_mcg"]?.state == .value(0))
        #expect(rows["magnesium_mg"]?.state == .noData)
        // A meal with no coverage record at all still renders its values.
        #expect(Self.rows(Self.meal(["vitamin_c_mg": 3]))["vitamin_c_mg"]?.state == .value(3))
    }

    @Test("Without the dictionary: the 34 legacy keys, named by the fallback, grouped, never a %")
    func noDictionary() {
        let source = MealNutrients.Source(totals: ["vitamin_c_mg": 12, "omega3_g": 1])
        let sections = MealNutrients.sections(source: source, catalogue: .empty, sex: .female, fallback: { "F:\($0)" })
        let all = sections.flatMap(\.rows)
        #expect(all.count == 34)
        #expect(all.allSatisfy { $0.percentOfReference == nil })
        let byGroup = Dictionary(sections.map { ($0.group, $0.rows.map(\.key)) }, uniquingKeysWith: { a, _ in a })
        #expect(byGroup[.vitamins]?.contains("vitamin_c_mg") == true)
        #expect(byGroup[.fattyAcids]?.contains("omega3_g") == true)
        #expect(byGroup[.minerals]?.contains("sodium_mg") == true)
        #expect(byGroup[.other]?.contains("choline_mg") == true)
        #expect(all.first { $0.key == "vitamin_c_mg" }?.name == "F:vitamin_c_mg")
        #expect(all.first { $0.key == "iron_mg" }?.state == .noData)
        // A key nobody can name is left out rather than shown as a raw key.
        let unnamed = MealNutrients.sections(source: source, catalogue: .empty, sex: nil, fallback: { $0 == "vitamin_c_mg" ? "C" : nil })
        #expect(unnamed.flatMap(\.rows).map(\.key) == ["vitamin_c_mg"])
    }

    // MARK: A day

    @Test("A day sums the analysed meals; partial when a meal lacks the key; traces only if every carrier was traces")
    func day() {
        let a = Self.meal(["vitamin_c_mg": 10, "selenium_mcg": 0], coverage: Self.coverage(byKey: ["vitamin_c_mg": 1, "selenium_mcg": 0.5], belowLimit: ["selenium_mcg": 0.5]))
        let b = Self.meal(["vitamin_c_mg": 5, "iron_mg": 2])
        let pending = Self.meal(["vitamin_c_mg": 100], status: .pricing)
        let source = MealNutrients.source(day: [a, b, pending], knownKeys: MealNutrients.knownKeys(Self.catalogue()))
        #expect(source.totals["vitamin_c_mg"] == 15)
        #expect(!source.partial.contains("vitamin_c_mg"))
        #expect(source.totals["iron_mg"] == 2)
        #expect(source.partial.contains("iron_mg"))
        #expect(source.traces == ["selenium_mcg"])
    }
}
