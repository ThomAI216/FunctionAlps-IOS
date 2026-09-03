import Foundation
import Testing
@testable import FunctionAlps

@Suite("PKCE + OAuth wire format")
struct OAuthTests {
    @Test func challengeIsS256OfVerifier() {
        // RFC 7636 appendix B vector
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.codeChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.codeVerifier().count >= 43)
        #expect(PKCE.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func authorizeURLCarriesPKCEAndRedirect() {
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport())
        let url = client.authorizeURL(provider: "google", codeChallenge: "abc")
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(url.path.hasSuffix("/auth/v1/authorize"))
        #expect(q.first { $0.name == "provider" }?.value == "google")
        #expect(q.first { $0.name == "code_challenge_method" }?.value == "s256")
        #expect(q.first { $0.name == "redirect_to" }?.value == "functionalps://auth/callback")
    }

    @Test func callbackParsing() throws {
        #expect(try OAuthCallback.code(from: URL(string: "functionalps://auth/callback?code=abc-123")!) == "abc-123")
        #expect(throws: AppError.self) {
            _ = try OAuthCallback.code(from: URL(string: "functionalps://auth/callback?error=access_denied&error_description=User+said+no")!)
        }
    }

    @Test func pkceExchangeAndIdTokenRequests() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "a2"))
        transport.enqueue(status: 200, json: Fixtures.tokenJSON(access: "a3"))
        let client = SupabaseAuthClient(environment: Fixtures.environment, transport: transport)

        let s1 = try await client.exchangeCode("code-1", codeVerifier: "ver-1")
        #expect(s1.accessToken == "a2")
        #expect(transport.requests[0].url.query == "grant_type=pkce")
        let b1 = String(decoding: transport.requests[0].body!, as: UTF8.self)
        #expect(b1.contains("\"auth_code\":\"code-1\"") && b1.contains("\"code_verifier\":\"ver-1\""))

        let s2 = try await client.signInWithIdToken(provider: "apple", idToken: "jwt", nonce: "raw")
        #expect(s2.accessToken == "a3")
        #expect(transport.requests[1].url.query == "grant_type=id_token")
        let b2 = String(decoding: transport.requests[1].body!, as: UTF8.self)
        #expect(b2.contains("\"provider\":\"apple\"") && b2.contains("\"id_token\":\"jwt\"") && b2.contains("\"nonce\":\"raw\""))
    }
}
