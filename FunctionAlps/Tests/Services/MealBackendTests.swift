import Foundation
import Testing
@testable import FunctionAlps

/// The meal wire format against CM OS: column names, body shapes, storage paths.
@Suite("SupabaseBackend — meals")
struct MealBackendTests {
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

    private func json(_ request: HTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func decodesFullMealRow() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"m1","logged_at":"2026-09-03T12:05:00.123456+00:00","meal_type":"lunch","name":"Chicken bowl","source":"photo","analysis_status":"complete","analysis_last_error":null,
          "total_calories":612,"total_protein_g":41.2,"total_carbs_g":55,"total_fat_g":22,"total_fiber_g":9,
          "photo_url":"uid/1.jpg","photo_urls":["uid/1.jpg","uid/2.jpg"],
          "ai_identified_foods":[{"name":"chicken","estimated_grams":120,"kcal":198,"protein_g":37,"carbs_g":0,"fat_g":4.3,"flags":["protein"]},{"name":"rice","estimated_grams":"150","kcal":195}],
          "inflammation_score":74.4,"glycemic_score":61,"gut_score":58,"patient_note":"Ate fast at my desk"}]
        """)
        let meal = try #require(try await make(transport).meal(id: "m1"))
        #expect(meal.status == .complete)
        #expect(meal.photoPaths == ["uid/1.jpg", "uid/2.jpg"])
        #expect(meal.items.count == 2)
        #expect(meal.items[0].flags == ["protein"])
        #expect(meal.items[1].estimatedGrams == 150)
        #expect(meal.scores == MealScores(inflammation: 74, glycemic: 61, digestion: 58))
        #expect(meal.patientNote == "Ate fast at my desk")
        #expect(meal.totalFiberG == 9)
        let query = try #require(transport.requests.first?.url.query)
        #expect(query.contains("id=eq.m1"))
        #expect(query.contains("patient_note"))
        #expect(!query.contains("ai_coaching_response"))
    }

    @Test func legacyRowsReadAsCompleteWithoutScores() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"old","logged_at":"2026-01-03T12:05:00Z","meal_type":"dinner","name":"Soup","source":null,"analysis_status":null,"total_calories":300,
          "photo_url":"https://example.supabase.co/storage/v1/object/public/meal-images/uid/old.jpg","photo_urls":null,"ai_identified_foods":{"unexpected":true},
          "inflammation_score":null,"glycemic_score":70,"gut_score":null,"patient_note":null}]
        """)
        let meal = try #require(try await make(transport).meal(id: "old"))
        #expect(meal.status == .complete)
        #expect(meal.isAnalysed)
        #expect(meal.scores == nil)
        #expect(meal.items.isEmpty)
        #expect(meal.photoPaths == ["uid/old.jpg"])
    }

    @Test func pendingRowCarriesNothingAnalysisDerived() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: #"[{"id":"new-1","patient_id":"p1"}]"#)
        let id = try await make(transport).createPendingMeal(PendingMealInput(
            patientId: "p1", mealType: .lunch, source: .text, description: "  chicken and rice  ", loggedAt: Date(timeIntervalSince1970: 1_788_350_000)
        ))
        #expect(id == "new-1")
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/nb_meal_logs"))
        #expect(request.headers["Prefer"] == "return=representation")
        let body = try json(request)
        #expect(body["patient_id"] as? String == "p1")
        #expect(body["meal_type"] as? String == "lunch")
        #expect(body["source"] as? String == "text")
        #expect(body["analysis_status"] as? String == "queued")
        #expect(body["name"] as? String == "chicken and rice")
        #expect(body["logged_at"] as? String == "2026-09-02T11:53:20.000Z")
        #expect(body["total_calories"] == nil)
        #expect(body["photo_url"] == nil)
        #expect(Set(body.keys) == ["patient_id", "meal_type", "source", "analysis_status", "name", "logged_at"])
    }

    @Test func photoMealHasNoName() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: #"[{"id":"new-2"}]"#)
        _ = try await make(transport).createPendingMeal(PendingMealInput(patientId: "p1", mealType: .snack, source: .photo, description: nil, loggedAt: Date()))
        let body = try json(try #require(transport.requests.first))
        #expect(body["name"] == nil)
    }

    @Test func attachPhotosKeepsElementZeroInBothColumns() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 204, json: "")
        try await make(transport).attachMealPhotos(mealId: "m1", paths: ["u/1.jpg", "u/2.jpg"])
        let request = try #require(transport.requests.first)
        #expect(request.method == .patch)
        #expect(request.url.query?.contains("id=eq.m1") == true)
        let body = try json(request)
        #expect(body["photo_url"] as? String == "u/1.jpg")
        #expect(body["photo_urls"] as? [String] == ["u/1.jpg", "u/2.jpg"])
    }

    @Test func analyzeBodyIsCamelCaseAndMatchesTheExpoShapes() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "{}")
        transport.enqueue(status: 200, json: "{}")
        transport.enqueue(status: 200, json: "{}")
        let backend = make(transport)
        try await backend.analyzeMeal(AnalyzeMealRequest(mealId: "m1", imageBase64s: ["AAA="]))
        try await backend.analyzeMeal(AnalyzeMealRequest(mealId: "m2", imageBase64s: ["AAA=", "BBB="]))
        try await backend.analyzeMeal(AnalyzeMealRequest(mealId: "m3", description: "oats", reanalyze: true))

        let single = try json(transport.requests[0])
        #expect(transport.requests[0].url.path.hasSuffix("/functions/v1/analyze-meal"))
        #expect(single["imageBase64"] as? String == "AAA=")
        #expect(single["imageBase64s"] == nil)
        #expect(single["mealLogId"] as? String == "m1")
        #expect(single["reanalyze"] == nil)
        #expect(single["meal_log_id"] == nil)

        let multi = try json(transport.requests[1])
        #expect(multi["imageBase64"] == nil)
        #expect(multi["imageBase64s"] as? [String] == ["AAA=", "BBB="])

        let text = try json(transport.requests[2])
        #expect(text["description"] as? String == "oats")
        #expect(text["reanalyze"] as? Bool == true)
        #expect(text["imageBase64"] == nil)
    }

    @Test func analyzeFailureSurfacesAsError() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 502, json: #"{"error":"Could not parse model output"}"#)
        await #expect(throws: AppError.self) {
            try await make(transport).analyzeMeal(AnalyzeMealRequest(mealId: "m1", description: "x"))
        }
    }

    @Test func noteUpdateSendsExplicitNull() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 204, json: "")
        transport.enqueue(status: 204, json: "")
        let backend = make(transport)
        try await backend.updateMealNote(mealId: "m1", note: nil)
        try await backend.updateMealNote(mealId: "m1", note: "Felt heavy")
        let cleared = try #require(transport.requests[0].body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(cleared.contains("\"patient_note\":null"))
        let set = try json(transport.requests[1])
        #expect(set["patient_note"] as? String == "Felt heavy")
        #expect(set["patient_note_updated_at"] is String)
    }

    @Test func deleteTargetsOneRow() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 204, json: "")
        try await make(transport).deleteMeal(id: "m9")
        let request = try #require(transport.requests.first)
        #expect(request.method == .delete)
        #expect(request.url.path.hasSuffix("/rest/v1/nb_meal_logs"))
        #expect(request.url.query == "id=eq.m9")
    }

    @Test func uploadGoesToTheAuthUsersFolder() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"Key":"meal-images/u1/1.jpg"}"#)
        let path = try await make(transport).uploadMealPhoto(userId: "u1", jpeg: Data([0xFF, 0xD8]))
        #expect(path.hasPrefix("u1/"))
        #expect(path.hasSuffix(".jpg"))
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path == "/storage/v1/object/meal-images/\(path)")
        #expect(request.headers["Content-Type"] == "image/jpeg")
        #expect(request.headers["x-upsert"] == "false")
        #expect(request.headers["Authorization"] == "Bearer access-1")
        #expect(request.body == Data([0xFF, 0xD8]))
    }

    @Test func signedURLIsAbsolute() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"signedURL":"/object/sign/meal-images/u1/1.jpg?token=abc"}"#)
        let url = try await make(transport).mealPhotoURL(path: "u1/1.jpg")
        #expect(url.absoluteString == "https://example.supabase.co/storage/v1/object/sign/meal-images/u1/1.jpg?token=abc")
        let request = try #require(transport.requests.first)
        #expect(request.url.path == "/storage/v1/object/sign/meal-images/u1/1.jpg")
        let body = try json(request)
        #expect(body["expiresIn"] as? Int == 3600)
    }

    @Test func removeSendsTheObjectList() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        try await make(transport).removeMealPhotos(paths: ["u1/1.jpg", "u1/2.jpg"])
        let request = try #require(transport.requests.first)
        #expect(request.method == .delete)
        #expect(request.url.path == "/storage/v1/object/meal-images")
        #expect(try json(request)["prefixes"] as? [String] == ["u1/1.jpg", "u1/2.jpg"])
    }
}
