import Foundation

/// One row of `member_pending_consents(p_locale, p_include_drafts)` — a consent the member can
/// accept or withdraw, with the exact wording CM OS holds for it (the text that was hashed).
struct ConsentItem: Decodable, Sendable, Equatable, Identifiable {
    enum Basis: String, Sendable { case contractCore = "contract_core", explicitConsent = "explicit_consent", optionalConsent = "optional_consent", unknown }

    let consentKey: String
    let version: String
    let title: String
    let summary: String
    let bodyMd: String
    let required: Bool
    let displayOrder: Int
    let reviewStatus: String
    let basisRaw: String?
    let accepted: Bool

    var id: String { consentKey }
    var basis: Basis { basisRaw.flatMap(Basis.init(rawValue:)) ?? .unknown }

    private enum CodingKeys: String, CodingKey {
        case consentKey, version, title, summary, bodyMd, required, displayOrder, reviewStatus, accepted
        case basisRaw = "basis"
    }
}

/// A document the member is SHOWN but does not agree to (privacy notice, legal notice, how AI is used):
/// the current approved `consent_definitions` row with `doc_kind = 'notice'`.
struct LegalDocument: Decodable, Sendable, Equatable, Identifiable {
    let consentKey: String
    let version: String
    let locale: String
    let title: String
    let summary: String?
    let bodyMd: String
    let displayOrder: Int?
    var id: String { consentKey }
}

/// Withdrawal rules — the Expo `lib/legal/manage.ts`. `basis` decides, not `required`: the Terms are
/// required AND contract_core (nothing to withdraw); health-data processing is required AND
/// explicit_consent (must be withdrawable even though withdrawing ends the service).
enum ConsentLogic {
    enum ManageKind: Sendable { case withdrawableCore, lockedCore, optional }

    static func manageKind(_ c: ConsentItem) -> ManageKind {
        if c.basis == .contractCore { return .lockedCore }
        if c.required { return .withdrawableCore }
        return .optional
    }

    static func withdrawalBlocksApp(_ c: ConsentItem) -> Bool { manageKind(c) == .withdrawableCore }
    static func isWithdrawable(_ c: ConsentItem) -> Bool { manageKind(c) != .lockedCore }

    struct Groups: Sendable, Equatable {
        let core: [ConsentItem]
        let optional: [ConsentItem]
    }

    static func group(_ consents: [ConsentItem]) -> Groups {
        let byOrder = consents.sorted { $0.displayOrder < $1.displayOrder }
        return Groups(core: byOrder.filter(\.required), optional: byOrder.filter { !$0.required })
    }

    static func hasUnapprovedDrafts(_ rows: [ConsentItem]) -> Bool {
        rows.contains { $0.reviewStatus != "approved" }
    }

    /// Every key on screen, `key@version` — ticks and notices alike (`presented_keys`).
    static func presentedKeys(_ consents: [ConsentItem], notices: [LegalDocument]) -> [String] {
        consents.map { "\($0.consentKey)@\($0.version)" } + notices.map { "\($0.consentKey)@\($0.version)" }
    }

    static func privacyNoticeVersion(_ notices: [LegalDocument]) -> String {
        notices.first { $0.consentKey == "privacy_policy" }.map { "\($0.consentKey)@\($0.version)" } ?? "unknown"
    }

    /// Bump when the acceptance SCREEN changes materially, not when wording changes.
    static let uiTemplateVersion = "ios-consent-manage-1"

    /// The three notices, in the catalogue's display order.
    static let noticeKeys = ["privacy_policy", "ai_analysis", "legal_notice"]

    /// The member's UI language as CM OS spells it (`en` / `fr`).
    static func locale(_ preferred: [String] = Locale.preferredLanguages) -> String {
        preferred.first.map { $0.lowercased().hasPrefix("fr") ? "fr" : "en" } ?? "en"
    }
}

/// The closed markdown subset `legalDocToMarkdown` emits: `## h2`, `### h3`, `- bullet`, paragraphs.
enum LegalMarkdown {
    enum Block: Sendable, Equatable {
        case h2(String)
        case h3(String)
        case paragraph(String)
        case bullets([String])
    }

    static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let chunks = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for raw in chunks {
            let chunk = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.isEmpty { continue }
            if chunk.hasPrefix("### ") { blocks.append(.h3(String(chunk.dropFirst(4)).trimmingCharacters(in: .whitespaces))); continue }
            if chunk.hasPrefix("## ") { blocks.append(.h2(String(chunk.dropFirst(3)).trimmingCharacters(in: .whitespaces))); continue }
            let lines = chunk.components(separatedBy: "\n")
            if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }) {
                blocks.append(.bullets(lines.map { String($0.trimmingCharacters(in: .whitespaces).dropFirst(2)).trimmingCharacters(in: .whitespaces) }))
                continue
            }
            blocks.append(.paragraph(chunk))
        }
        return blocks
    }
}
