import Foundation
import Testing
@testable import FunctionAlps

@Suite("AppError mapping")
struct AppErrorTests {
    @Test func mapsStatuses() {
        #expect(AppError.fromStatus(401, body: Data()) == .unauthorized)
        #expect(AppError.fromStatus(403, body: Data()) == .forbidden)
        #expect(AppError.fromStatus(404, body: Data()) == .notFound)
        #expect(AppError.fromStatus(503, body: Data()) == .server(status: 503))
    }

    @Test func extractsPostgRESTMessage() {
        let body = Data(#"{"code":"23505","details":null,"hint":null,"message":"duplicate key value"}"#.utf8)
        #expect(AppError.fromStatus(409, body: body) == .validation(message: "duplicate key value"))
    }

    @Test func userMessagesNeverLeakDetail() {
        let error = AppError.decoding(detail: "keyNotFound(CodingKeys(stringValue: \"access_token\"))")
        #expect(!error.userMessage.contains("access_token"))
        #expect(error.debugDescription.contains("access_token"))
    }

    @Test func gotrueNewAndLegacyErrorShapes() {
        let new = HTTPResponse(status: 400, headers: [:], body: Data(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#.utf8))
        let legacy = HTTPResponse(status: 400, headers: [:], body: Data(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#.utf8))
        #expect(SupabaseAuthClient.mapAuthError(new) == .invalidCredentials)
        #expect(SupabaseAuthClient.mapAuthError(legacy) == .invalidCredentials)
        let limited = HTTPResponse(status: 429, headers: [:], body: Data())
        if case .validation = SupabaseAuthClient.mapAuthError(limited) {} else { Issue.record("429 should be a validation-style message") }
    }
}
