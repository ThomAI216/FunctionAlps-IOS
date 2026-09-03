import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseAuthClient")
struct SupabaseAuthClientTests {
    @Test func signInDecodesSessionAndSendsCredentials() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: Fixtures.tokenJSON())
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)

        let session = try await client.signIn(email: "member@example.com", password: "secret")

        #expect(session.accessToken == "access-1")
        #expect(session.refreshToken == "refresh-1")
        #expect(session.userId == "11111111-2222-3333-4444-555555555555")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 4_102_444_800))

        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=password")
        #expect(request.headers["apikey"] == "sb_publishable_test")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["email"] == "member@example.com")
        #expect(json["password"] == "secret")
    }

    @Test func wrongPasswordIsInvalidCredentials() async {
        let transport = MockTransport()
        transport.enqueue(status: 400, json: #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#)
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)
        await #expect(throws: AppError.invalidCredentials) {
            _ = try await client.signIn(email: "a@b.c", password: "nope")
        }
    }

    @Test func refreshUsesRefreshGrant() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "access-2", refresh: "refresh-2"))
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)
        let session = try await client.refresh(refreshToken: "refresh-1")
        #expect(session.accessToken == "access-2")
        #expect(transport.requests.first?.url.query == "grant_type=refresh_token")
        let body = try #require(transport.requests.first?.body)
        #expect(String(decoding: body, as: UTF8.self).contains("\"refresh_token\":\"refresh-1\""))
    }

    @Test func rejectedRefreshIsUnauthorized() async {
        let transport = MockTransport()
        transport.enqueue(status: 400, json: #"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#)
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)
        await #expect(throws: AppError.unauthorized) {
            _ = try await client.refresh(refreshToken: "stale")
        }
    }

    @Test func signOutToleratesAlreadyInvalidToken() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 401, json: #"{"msg":"invalid JWT"}"#)
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)
        try await client.signOut(accessToken: "old")
        #expect(transport.requests.first?.headers["Authorization"] == "Bearer old")
    }
}
