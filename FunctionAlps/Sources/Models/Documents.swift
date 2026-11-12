import Foundation

// The member's documents — what the care team released to them (Documents tab programme, 2026-11-11).
// Source of truth: the CM OS functions `member_documents()`, `member_document_file(p_release_id)`,
// `member_mark_document_seen(p_release_id)` and `member_has_draft_plan()` (SECURITY DEFINER, JWT only).
// A member sees a document ONLY through a live release (`sent_at` set, `revoked_at` null); the database
// decides that, never this app. Foundation only, so the whole file runs under Swift Testing.

/// What a document is. The raw values are the `document_releases.kind` check list. An unknown future
/// kind decodes as `.file` (a plain file) rather than failing the whole list.
enum DocumentKind: String, Sendable, Equatable, CaseIterable {
    case report, carePlan = "care_plan", labReport = "lab_report", resource, invoice, contract, brochure, file

    init(wire: String?) { self = wire.flatMap(DocumentKind.init(rawValue:)) ?? .file }

    /// The colour of the kind (R2 iOS mockup). Status is never by colour alone: the card also carries
    /// the icon and the kind's name. `contract` and `file` are not on the mockup; they take their own hues.
    var tintHex: UInt32 {
        switch self {
        case .report: 0x2E5438
        case .carePlan: 0x1F6F66
        case .labReport: 0x6B3F8A
        case .resource: 0x2B5C82
        case .invoice: 0x8A5A0B
        case .contract: 0x7A3E5A
        case .brochure: 0x9A4A2E
        case .file: 0x3D4F6B
        }
    }

    var symbol: String {
        switch self {
        case .report: "doc.text"
        case .carePlan: "checklist"
        case .labReport: "testtube.2"
        case .resource: "link"
        case .invoice: "receipt"
        case .contract: "signature"
        case .brochure: "book.closed"
        case .file: "paperclip"
        }
    }

    var label: String {
        switch self {
        case .report: String(localized: "documents.kind.report", defaultValue: "Report")
        case .carePlan: String(localized: "documents.kind.carePlan", defaultValue: "Care plan")
        case .labReport: String(localized: "documents.kind.labReport", defaultValue: "Lab report")
        case .resource: String(localized: "documents.kind.resource", defaultValue: "Resource")
        case .invoice: String(localized: "documents.kind.invoice", defaultValue: "Invoice")
        case .contract: String(localized: "documents.kind.contract", defaultValue: "Contract")
        case .brochure: String(localized: "documents.kind.brochure", defaultValue: "Brochure")
        case .file: String(localized: "documents.kind.file", defaultValue: "File")
        }
    }
}

/// One row of `member_documents()`. Columns in camelCase (`JSON.decoder` converts).
struct MemberDocument: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let kind: DocumentKind
    let title: String
    let sentAt: Date?
    let firstSeenAt: Date?
    let hasFile: Bool
    let linkPath: String?
    let hasPreview: Bool
    let fromName: String?

    init(id: String, kind: DocumentKind, title: String, sentAt: Date? = nil, firstSeenAt: Date? = nil,
         hasFile: Bool = true, linkPath: String? = nil, hasPreview: Bool = false, fromName: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.sentAt = sentAt; self.firstSeenAt = firstSeenAt
        self.hasFile = hasFile; self.linkPath = linkPath; self.hasPreview = hasPreview; self.fromName = fromName
    }

    private enum CodingKeys: String, CodingKey { case id, kind, title, sentAt, firstSeenAt, hasFile, linkPath, hasPreview, fromName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = DocumentKind(wire: try c.decodeIfPresent(String.self, forKey: .kind))
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        hasFile = try c.decodeIfPresent(Bool.self, forKey: .hasFile) ?? false
        linkPath = try c.decodeIfPresent(String.self, forKey: .linkPath)
        hasPreview = try c.decodeIfPresent(Bool.self, forKey: .hasPreview) ?? false
        fromName = try c.decodeIfPresent(String.self, forKey: .fromName)
    }

    /// Unseen = the member has not opened it yet (the "New" marker).
    var isNew: Bool { firstSeenAt == nil }
}

/// One row of `member_document_file(p_release_id)`: where the frozen copy lives, or the in-app link.
struct DocumentFile: Decodable, Sendable, Equatable {
    let storageBucket: String?
    let storagePath: String?
    let linkPath: String?
    let previewPath: String?

    init(storageBucket: String? = nil, storagePath: String? = nil, linkPath: String? = nil, previewPath: String? = nil) {
        self.storageBucket = storageBucket; self.storagePath = storagePath
        self.linkPath = linkPath; self.previewPath = previewPath
    }

    /// The function returns a table (an array of at most one row); a bare object is accepted too.
    static func decode(_ data: Data) throws -> DocumentFile? {
        if let rows = try? JSON.decode([DocumentFile].self, from: data) { return rows.first }
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
        return try JSON.decode(DocumentFile.self, from: data)
    }
}

/// The segmented filter on the list. `Invoices` also holds the contract; `Resources` also holds brochures.
enum DocumentFilter: String, Sendable, CaseIterable, Identifiable {
    case all, reports, labReports, resources, invoices
    var id: String { rawValue }

    func includes(_ kind: DocumentKind) -> Bool {
        switch self {
        case .all: true
        case .reports: kind == .report
        case .labReports: kind == .labReport
        case .resources: kind == .resource || kind == .brochure
        case .invoices: kind == .invoice || kind == .contract
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "documents.filter.all", defaultValue: "All")
        case .reports: String(localized: "documents.filter.reports", defaultValue: "Reports")
        case .labReports: String(localized: "documents.filter.labReports", defaultValue: "Lab reports")
        case .resources: String(localized: "documents.filter.resources", defaultValue: "Resources")
        case .invoices: String(localized: "documents.filter.invoices", defaultValue: "Invoices")
        }
    }
}

/// Where a tapped document goes.
enum DocumentDestination: Sendable, Equatable {
    /// A signed storage URL (a PDF or a file) or a members-site page, shown in the in-app browser.
    case browser(URL)
    /// The current plan: the app's own plan page.
    case plan
}

enum DocumentsLogic {
    /// The members web app: the only host a `link_path` may open (a release can never send a member elsewhere).
    static let membersBase = URL(string: "https://members.functionalps.ch")!
    /// Buckets a document can be signed from (RLS lets a member read only her own live releases there).
    static let allowedBuckets: Set<String> = ["document-releases", "invoices"]
    /// Signed URLs live ten minutes: long enough to open and read, short enough not to be shared.
    static let signedURLSeconds = 600

    /// Newest sent first; a row with no date goes last. Stable for equal dates.
    static func sorted(_ docs: [MemberDocument]) -> [MemberDocument] {
        docs.enumerated().sorted { a, b in
            switch (a.element.sentAt, b.element.sentAt) {
            case let (x?, y?): x != y ? x > y : a.offset < b.offset
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    static func filtered(_ docs: [MemberDocument], by filter: DocumentFilter) -> [MemberDocument] {
        sorted(docs).filter { filter.includes($0.kind) }
    }

    static func unseenCount(_ docs: [MemberDocument]) -> Int { docs.filter(\.isNew).count }

    /// `link_path` → an https URL on the members site, or nil. A path ("/dashboard/…") is joined to the base;
    /// an absolute URL is accepted only when it already points at the members host over https.
    static func webURL(linkPath: String?) -> URL? {
        guard let raw = linkPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") && !raw.hasPrefix("//") {
            return URL(string: membersBase.absoluteString + raw)
        }
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == membersBase.host else { return nil }
        return url
    }

    /// "10 Nov 2026 · Thomas" — the date, then the sender's first name when there is one.
    static func subtitle(_ doc: MemberDocument) -> String {
        var parts: [String] = []
        if let date = doc.sentAt { parts.append(date.formatted(.dateTime.day().month(.abbreviated).year())) }
        if let first = doc.fromName?.split(separator: " ").first.map(String.init), !first.isEmpty { parts.append(first) }
        return parts.joined(separator: " · ")
    }

    /// Decides what a tap does from the document and its file row. Pure, so the rules are testable.
    /// The signing itself (a network call) is the service's job: this returns the bucket and path to sign.
    enum Plan: Equatable {
        case sign(bucket: String, path: String)
        case destination(DocumentDestination)
        case unavailable
    }

    static func plan(for doc: MemberDocument, file: DocumentFile?) -> Plan {
        if doc.hasFile, let bucket = file?.storageBucket, let path = file?.storagePath, !path.isEmpty {
            return allowedBuckets.contains(bucket) ? .sign(bucket: bucket, path: path) : .unavailable
        }
        if doc.kind == .carePlan { return .destination(.plan) }
        if let url = webURL(linkPath: file?.linkPath ?? doc.linkPath) { return .destination(.browser(url)) }
        return .unavailable
    }
}
