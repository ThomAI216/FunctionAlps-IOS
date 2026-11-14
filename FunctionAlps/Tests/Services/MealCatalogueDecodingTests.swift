import Foundation
import Testing
@testable import FunctionAlps

/// The stored shape `analyze-meal` writes for the full catalogue (`resolution_meta.micro_coverage.by_key`,
/// `below_limit`, `nutrient_metrics`), old meals without it, and the dictionary / reference reads.
@Suite("SupabaseBackend — meal nutrient catalogue")
struct MealCatalogueDecodingTests {
    private func make(_ transport: MockTransport) -> SupabaseBackend {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        return SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester)
        )
    }

    @Test func decodesTheNewResolutionMeta() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"m1","logged_at":"2026-11-14T12:00:00+00:00","analysis_status":"complete",
          "micronutrient_totals":{"vitamin_c_mg":12,"sfa_4_0_g":0.1,"selenium_mcg":0},
          "micro_coverage":{"tracked":34,"measured":30,"items":3,"items_from_catalogue":3,"partial":["iron_mg"],
            "by_key":{"vitamin_c_mg":1,"sfa_4_0_g":0.5,"selenium_mcg":0.4},"below_limit":{"selenium_mcg":0.4},
            "catalogue_tracked":120,"catalogue_measured":80},
          "nutrient_metrics":{"omega6_omega3_ratio":{"value":4.2,"status":"complete","coverage":1},
            "epa_dha_mg":{"value":120,"status":"partial","coverage":0.6}}}]
        """)
        let meal = try #require(try await make(transport).meal(id: "m1"))
        let coverage = try #require(meal.microCoverage)
        #expect(coverage.partial == ["iron_mg"])
        #expect(coverage.byKey?["vitamin_c_mg"] == 1)
        #expect(coverage.belowLimit?["selenium_mcg"] == 0.4)
        #expect(coverage.catalogueTracked == 120)
        #expect(coverage.catalogueMeasured == 80)
        #expect(meal.nutrientMetrics?["omega6_omega3_ratio"] == MealNutrientMetric(value: 4.2, status: "complete", coverage: 1))
        #expect(meal.nutrientMetrics?["epa_dha_mg"]?.isComplete == false)
        // `url.query` is percent-encoded ("->" travels as "-%3E"); compare the decoded text.
        let query = try #require(transport.requests.first?.url.query?.removingPercentEncoding)
        #expect(query.contains("nutrient_metrics:resolution_meta->nutrient_metrics"))

        // End to end: the decoder mangles `sfa_4_0_g`; the source recovers it, with its share.
        let source = MealNutrients.source(meal: meal, knownKeys: ["sfa_4_0_g", "vitamin_c_mg", "selenium_mcg"])
        #expect(source.totals["sfa_4_0_g"] == 0.1)
        #expect(source.partial.contains("sfa_4_0_g"))
        #expect(source.traces == ["selenium_mcg"])
    }

    @Test func oldMealDecodesWithoutTheNewFields() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"m0","logged_at":"2026-09-03T12:00:00+00:00","analysis_status":"complete",
          "micronutrient_totals":{"vitamin_c_mg":12,"iron_mg":2},
          "micro_coverage":{"tracked":34,"measured":2,"items":2,"items_from_catalogue":2,"partial":["iron_mg"]}}]
        """)
        let meal = try #require(try await make(transport).meal(id: "m0"))
        let coverage = try #require(meal.microCoverage)
        #expect(coverage.tracked == 34)
        #expect(coverage.partial == ["iron_mg"])
        #expect(coverage.byKey == nil)
        #expect(coverage.belowLimit == nil)
        #expect(coverage.catalogueTracked == nil)
        #expect(meal.nutrientMetrics == nil)
        #expect(meal.micros == ["vitamin_c_mg": 12, "iron_mg": 2])
    }

    @Test func anOddMetricsShapeIsNotRecordedAndTheMealStillLoads() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"m2","logged_at":"2026-11-14T12:00:00+00:00",
          "micronutrient_totals":{"vitamin_c_mg":12},
          "micro_coverage":{"tracked":34,"measured":1,"items":1,"items_from_catalogue":1,"partial":[],"by_key":"oops"},
          "nutrient_metrics":"oops"}]
        """)
        let meal = try #require(try await make(transport).meal(id: "m2"))
        #expect(meal.nutrientMetrics == nil)
        #expect(meal.microCoverage?.tracked == 34)
        #expect(meal.microCoverage?.byKey == nil)
    }

    @Test func readsTheDictionaryByName() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"key":"vitamin_c_mg","name":"Vitamin C","group_code":"vitamin","unit":"mg","sort_order":72,"hold_reason":null},
         {"key":"vitamin_k2_mcg","name":"Vitamin K2 (menaquinone-4)","group_code":"vitamin","unit":"mcg","sort_order":70,"hold_reason":"on hold"},
         {"key":"broken","name":null,"group_code":"other","unit":"mg","sort_order":200,"hold_reason":null}]
        """)
        let definitions = try await make(transport).nutrientDictionary()
        #expect(definitions == [
            NutrientDefinition(key: "vitamin_c_mg", name: "Vitamin C", groupCode: "vitamin", unit: "mg", sortOrder: 72, holdReason: nil),
            NutrientDefinition(key: "vitamin_k2_mcg", name: "Vitamin K2 (menaquinone-4)", groupCode: "vitamin", unit: "mcg", sortOrder: 70, holdReason: "on hold"),
        ])
        let url = try #require(transport.requests.first?.url.absoluteString)
        #expect(url.contains("/nb_nutrients"))
        #expect(url.contains("hold_reason"))
    }

    @Test func readsTheAdultReferenceIntakes() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"nutrient_key":"vitamin_c_mg","set_code":"efsa_drv_2017","sex":"female","life_stage":"adult","kind":"PRI","amount":95,"unit":"mg"},
         {"nutrient_key":"epa_dha_mg","set_code":"efsa_drv_2017","sex":"any","life_stage":"adult","kind":"AI","amount":null,"unit":"mg"}]
        """)
        let refs = try await make(transport).nutrientReferenceIntakes()
        #expect(refs == [NutrientReference(nutrientKey: "vitamin_c_mg", setCode: "efsa_drv_2017", sex: "female", lifeStage: "adult", kind: "PRI", amount: 95, unit: "mg")])
        let url = try #require(transport.requests.first?.url.absoluteString)
        #expect(url.contains("/nutrient_reference_intakes_daily"))
        #expect(url.contains("life_stage=eq.adult"))
    }
}
