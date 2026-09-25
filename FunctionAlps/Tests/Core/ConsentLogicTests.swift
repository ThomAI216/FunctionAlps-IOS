import Foundation
import Testing
@testable import FunctionAlps

@Suite("ConsentLogic — re-acceptance")
struct ConsentLogicTests {
    private func item(_ key: String, version: String, required: Bool = true, accepted: Bool = false, held: String? = nil) -> ConsentItem {
        ConsentItem(consentKey: key, version: version, title: key, summary: "", bodyMd: "",
                    required: required, displayOrder: 10, reviewStatus: "approved", basisRaw: "contract_core",
                    accepted: accepted, acceptedVersion: held)
    }

    // isUpdate — "this exact document moved under you"

    @Test func aHeldOlderVersionIsAnUpdate() {
        #expect(ConsentLogic.isUpdate(item("terms_of_use", version: "v8", held: "v7")))
    }

    @Test func whatTheMemberAlreadySignedIsNotAnUpdate() {
        #expect(!ConsentLogic.isUpdate(item("terms_of_use", version: "v8", accepted: true, held: "v8")))
    }

    @Test func neverAgreedIsNotAnUpdate() {
        // A first sitting, and a never-seen item added to an existing screen, both read as "new", not "changed".
        #expect(!ConsentLogic.isUpdate(item("terms_of_use", version: "v8", held: nil)))
        #expect(!ConsentLogic.isUpdate(item("terms_of_use", version: "v8", held: "")))
    }

    // isReAcceptance — which wording the whole screen wears

    @Test func aFirstSittingIsNotAReAcceptance() {
        #expect(!ConsentLogic.isReAcceptance([
            item("terms_of_use", version: "v8"),
            item("health_data_processing", version: "v6"),
        ]))
    }

    @Test func anyStandingGrantMakesItAReAcceptance() {
        // Terms moved v7 → v8; the health-data consent is untouched and still signed.
        #expect(ConsentLogic.isReAcceptance([
            item("terms_of_use", version: "v8", held: "v7"),
            item("health_data_processing", version: "v6", accepted: true, held: "v6"),
        ]))
        // A brand-new required item next to one they already hold is still a returning member.
        #expect(ConsentLogic.isReAcceptance([
            item("wearables_consent", version: "v1"),
            item("terms_of_use", version: "v8", accepted: true, held: "v8"),
        ]))
    }

    // The column is new: a build must survive meeting the RPC that does not send it yet.

    @Test func decodesWithAndWithoutTheNewColumn() throws {
        let withColumn = Data("""
        [{"consent_key":"terms_of_use","version":"v8","title":"Terms","summary":"s","body_md":"b",
          "required":true,"display_order":10,"review_status":"approved","basis":"contract_core",
          "accepted":false,"accepted_version":"v7"}]
        """.utf8)
        let rows = try JSON.decoder.decode([ConsentItem].self, from: withColumn)
        #expect(rows.first?.acceptedVersion == "v7")
        #expect(ConsentLogic.isUpdate(try #require(rows.first)))

        // Pre-migration shape: no accepted_version at all.
        let without = Data("""
        [{"consent_key":"terms_of_use","version":"v8","title":"Terms","summary":"s","body_md":"b",
          "required":true,"display_order":10,"review_status":"approved","basis":"contract_core",
          "accepted":false}]
        """.utf8)
        let legacy = try JSON.decoder.decode([ConsentItem].self, from: without)
        #expect(legacy.first?.acceptedVersion == nil)
        #expect(!ConsentLogic.isReAcceptance(legacy))   // falls back to the first-run wording
    }
}

@Suite("ConsentLogic — why a save failed")
struct ConsentSaveFailureTests {
    /// 403 is the server saying "no member behind this session". Telling the member to check their
    /// connection sends them retrying a refusal — it did, four times, on 2026-09-25.
    @Test func aRefusedSessionIsNotAConnectionProblem() {
        #expect(ConsentLogic.saveFailure(AppError.forbidden) == .notLinked)
    }

    @Test func offlineIsWorthRetrying() {
        #expect(ConsentLogic.saveFailure(AppError.offline) == .connection)
        #expect(ConsentLogic.saveFailure(AppError.network(detail: "timed out")) == .connection)
    }

    @Test func aDraftIsNamedAsSuch() {
        #expect(ConsentLogic.saveFailure(AppError.validation(message: "consent definition terms_of_use/v9 is not approved (draft)")) == .draft)
    }

    @Test func anythingElseIsNotBlamedOnTheConnection() {
        #expect(ConsentLogic.saveFailure(AppError.server(status: 500)) == .other)
        #expect(ConsentLogic.saveFailure(AppError.validation(message: "member is not confirmed as 18 or older")) == .other)
        #expect(ConsentLogic.saveFailure(AppError.decoding(detail: "rpc")) == .other)
    }
}
