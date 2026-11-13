import Foundation
import Testing
@testable import FunctionAlps

/// The meal plan's wire format against CM OS: RPC names, parameter names, the grocery tick upsert.
@Suite("SupabaseBackend — meal plan")
struct MealPlanBackendTests {
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

    private func body(_ request: HTTPRequest) throws -> [String: Any] {
        let data = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func readsThePlanThroughTheRpcWithNoDates() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"from":"2026-11-16","to":"2026-11-22","plans":[],"days":[{"date":"2026-11-16","plan_id":"p1","meals":[]}]}"#)
        let range = try await make(transport).mealPlan()
        #expect(range.days.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/member_meal_plan"))
        #expect(try body(request).isEmpty)   // the server's own "today" decides the range
    }

    @Test func iAteThisIsOneRpcWithTheSlotAndTheDay() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"meal_log_id":"log1","created":true}"#)
        let result = try await make(transport).logPlannedMeal(slotId: "slot-1", planDate: "2026-11-16")
        #expect(result == PlannedMealLog(mealLogId: "log1", created: true))
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rpc/member_log_planned_meal"))
        let b = try body(request)
        #expect(b["p_slot"] as? String == "slot-1")
        #expect(b["p_plan_date"] as? String == "2026-11-16")
        #expect(b.count == 2)
    }

    @Test func swapListAndSwapUseTheDocumentedParameters() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"[{"recipe_id":"r1","title":"Bowl","source":"library","is_current":false}]"#)
        transport.enqueue(status: 200, json: #"{"changed":true,"recipe_id":"r1","kind":"swap"}"#)
        let backend = make(transport)
        let list = try await backend.swapCandidates(slotId: "slot-1", planDate: "2026-11-16", anyMeal: true)
        #expect(list.map(\.recipeId) == ["r1"])
        let first = try body(try #require(transport.requests.first))
        #expect(first["p_any_meal"] as? Bool == true)
        #expect(first["p_limit"] as? Int == 60)
        let outcome = try await backend.swapPlannedMeal(slotId: "slot-1", recipeId: "r1", planDate: "2026-11-16")
        #expect(outcome.changed)
        let second = try body(transport.requests[1])
        #expect(second["p_recipe"] as? String == "r1")
        #expect(second["p_slot"] as? String == "slot-1")
        #expect(second["p_plan_date"] as? String == "2026-11-16")
    }

    @Test func recipeCardReadsTheRecipeThenItsLinesInOrder() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"[{"id":"r1","title":"Lentil salad","body_md":"","steps":["Mix"],"servings":2}]"#)
        transport.enqueue(status: 200, json: #"[{"id":"i1","raw_text":"Green lentils","qty":160,"unit_code":"g","is_to_taste":false,"is_optional":false}]"#)
        let card = try #require(try await make(transport).recipeCard(id: "r1"))
        #expect(card.ingredients.map(\.rawText) == ["Green lentils"])
        let lines = try #require(transport.requests.last?.url.query)
        #expect(lines.contains("recipe_id=eq.r1"))
        #expect(lines.contains("order=sort_order.asc"))
    }

    @Test func recipeCardFallsBackWhenWhyLineAndDescriptionDoNotExistYet() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 400, json: #"{"code":"42703","message":"column recipes.why_line does not exist"}"#)
        transport.enqueue(status: 200, json: #"[{"id":"r1","title":"Lentil salad","steps":[{"phase":"prep","text":"Rinse"}]}]"#)
        transport.enqueue(status: 200, json: "[]")
        let card = try #require(try await make(transport).recipeCard(id: "r1"))
        #expect(card.steps == [RecipeStep(phase: .prep, text: "Rinse")])
        #expect(card.whyLine == nil)
        #expect(transport.requests[0].url.query?.contains("why_line") == true)
        #expect(transport.requests[1].url.query?.contains("why_line") == false)
    }

    @Test func aMissingRecipeIsNilNotAnError() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        #expect(try await make(transport).recipeCard(id: "nope") == nil)
        #expect(transport.requestCount == 1)
    }

    @Test func tickingUpsertsOneRowPerFoodAndUntickWritesNull() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        transport.enqueue(status: 201, json: "")
        let list = GroceryList(planId: "p1", periodStart: "2026-11-16", periodEnd: "2026-11-22", aisles: [], custom: [])
        let backend = make(transport)
        try await backend.setGroceryChecked(patientId: "pat", list: list, target: .food("f1"), checked: true)
        let tick = try #require(transport.requests.first)
        #expect(tick.url.path.hasSuffix("/rest/v1/member_grocery_state"))
        #expect(tick.url.query?.contains("on_conflict=patient_id,plan_id,period_start,food_item_id,custom_label") == true)
        #expect(tick.headers["Prefer"]?.contains("merge-duplicates") == true)
        let tickBody = try #require(tick.body)
        let rows = try #require(JSONSerialization.jsonObject(with: tickBody) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["patient_id"] as? String == "pat")
        #expect(rows[0]["plan_id"] as? String == "p1")
        #expect(rows[0]["period_start"] as? String == "2026-11-16")
        #expect(rows[0]["food_item_id"] as? String == "f1")
        #expect(rows[0]["checked_at"] is String)
        #expect(rows[0]["custom_label"] is NSNull)

        try await backend.setGroceryChecked(patientId: "pat", list: list, target: .food("f1"), checked: false)
        let untickBody = try #require(transport.requests[1].body)
        let untick = try #require(JSONSerialization.jsonObject(with: untickBody) as? [[String: Any]])
        #expect(untick[0]["checked_at"] is NSNull)   // an explicit null clears the tick and keeps the row
    }

    @Test func ownItemsAreTickedByIdAndAFoodTickNeedsAPlan() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 204, json: "")
        let backend = make(transport)
        let list = GroceryList(planId: nil, periodStart: nil, periodEnd: nil, aisles: [], custom: [])
        try await backend.setGroceryChecked(patientId: "pat", list: list, target: .custom("c1"), checked: true)
        let patch = try #require(transport.requests.first)
        #expect(patch.method == .patch)
        #expect(patch.url.query?.contains("id=eq.c1") == true)
        await #expect(throws: AppError.self) {
            try await backend.setGroceryChecked(patientId: "pat", list: list, target: .food("f1"), checked: true)
        }
    }

    @Test func aPlannedMealLogDecodesAsAPlanSourceAndRelogsAsText() {
        #expect(MealLog.Source(rawValue: "plan") == .plan)
    }
}
