import Foundation
import Testing
@testable import FunctionAlps

@Suite("MemberScores (member-scores wire format)")
struct ScoresTests {
    @Test func decodesTheEngineResponse() throws {
        let json = """
        {"day":"2026-09-03","tzOffsetMinutes":120,"generatedAt":"2026-09-03T12:00:00.000Z","trend":"flat",
         "inputs":{"meals":3,"functionalDays":3,"gutDays":0,"hasToday":true,"hasProfile":true},
         "vitality":{"score":59,"factors":[{"key":"energy","label":"Energy","value":69,"weight":0.3,"status":"good"},{"key":"recovery","label":"Recovery","value":null,"weight":0.2,"status":"watch"}],"series14d":[null,60,59],"tip":{"summary":"Your {label} is holding steady.","good":"Energy is your strongest driver (69/100).","bad":"Stress is the weak point (50/100) · focus here."}},
         "metabolic":{"score":69,"factors":[],"series14d":[],"tip":null},
         "nutrition":{"score":40,"factors":[],"series14d":[],"tip":null},
         "gut":{"score":null,"factors":[],"series14d":[null],"tip":{"summary":"Log a little more and your {label} reading appears here.","good":"","bad":""}},
         "composite":{"score":58,"basis":"checkins+nutrition","pillars":{"vitality":59,"metabolic":69,"nutrition":40}},
         "compositeSeries14d":[null,null,64,59,59,58]}
        """
        let scores = try JSON.decode(MemberScores.self, from: Data(json.utf8))
        #expect(scores.composite.intScore == 58)
        #expect(scores.trend == .flat)
        #expect(scores.vitality.factors.count == 2)
        #expect(scores.vitality.factors[0].intValue == 69)
        #expect(scores.vitality.factors[1].value == nil)
        #expect(scores.vitality.tip?.summaryText(label: "Vitality") == "Your Vitality is holding steady.")
        #expect(scores.crownSeries == [nil, nil, 64, 59, 59, 58])
        #expect(scores.gut.intScore == nil)
        #expect(scores.breakdown(.nutrition).intScore == 40)
    }

    @Test func unknownTrendDecodesAsNil() throws {
        let json = """
        {"day":"2026-09-03","trend":null,"vitality":{"score":null,"factors":[],"series14d":[],"tip":null},"metabolic":{"score":null,"factors":[],"series14d":[],"tip":null},"nutrition":{"score":null,"factors":[],"series14d":[],"tip":null},"gut":{"score":null,"factors":[],"series14d":[],"tip":null},"composite":{"score":null,"basis":"none","pillars":{"vitality":null,"metabolic":null,"nutrition":null}},"compositeSeries14d":[]}
        """
        let scores = try JSON.decode(MemberScores.self, from: Data(json.utf8))
        #expect(scores.trend == nil)
        #expect(scores.composite.intScore == nil)
    }

    @Test func scoresRequestCarriesTheOffsetInCamelCase() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        {"day":"2026-09-03","trend":"up","vitality":{"score":1,"factors":[],"series14d":[],"tip":null},"metabolic":{"score":1,"factors":[],"series14d":[],"tip":null},"nutrition":{"score":1,"factors":[],"series14d":[],"tip":null},"gut":{"score":1,"factors":[],"series14d":[],"tip":null},"composite":{"score":1,"basis":"checkins","pillars":{"vitality":1,"metabolic":1,"nutrition":1}},"compositeSeries14d":[1]}
        """)
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        let backend = SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester)
        )
        let scores = try await backend.memberScores(tzOffsetMinutes: 120)
        #expect(scores.trend == .up)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/functions/v1/member-scores"))
        let body = try #require(request.body)
        #expect(String(decoding: body, as: UTF8.self) == #"{"tzOffsetMinutes":120}"#)
    }
}
