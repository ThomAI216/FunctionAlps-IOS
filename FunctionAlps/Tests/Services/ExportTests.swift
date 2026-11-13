import Foundation
import Testing
@testable import FunctionAlps

/// "Export my data" (owner, 2026-11-12): no pattern the practitioner has not validated.
/// `nb_user_patterns_self_select` (RLS) returns only validated, patient-visible rows to the member's own session, so the
/// export is compliant as long as it reads through that session — `AccountService.exportBundle` → `backend.dataRows`.
@Suite("Data export")
struct ExportTests {
    @Test("Patterns are read through the member-session path (RLS-filtered), and the bundle carries them")
    func patternsComeFromTheMemberSession() async throws {
        let backend = RecordingBackend()
        let data = await AccountService(backend: backend).exportBundle(patientId: "p1")
        #expect(backend.calls.contains("rows:nb_user_patterns"))
        #expect(ExportTables.ordered.contains { $0.key == "patterns" && $0.table == "nb_user_patterns" })
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["patterns"] != nil)
        #expect(json["userId"] as? String == "p1")
    }
}
