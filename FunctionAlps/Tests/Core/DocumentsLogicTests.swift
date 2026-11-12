import Foundation
import Testing
@testable import FunctionAlps

@Suite("Documents — decoding, filters, rules")
struct DocumentsLogicTests {
    static let json = """
    [
     {"id":"r1","kind":"lab_report","title":"Iron & thyroid","sent_at":"2026-11-10T09:00:00.123+00:00","first_seen_at":null,"has_file":true,"link_path":null,"has_preview":true,"from_name":"Thomas Convent"},
     {"id":"r2","kind":"report","title":"Your expert consultation","sent_at":"2026-11-07T09:00:00+00:00","first_seen_at":"2026-11-08T10:00:00+00:00","has_file":true,"link_path":null,"has_preview":false,"from_name":"Alessandra Ginsburg"},
     {"id":"r3","kind":"resource","title":"Low-FODMAP ladder","sent_at":"2026-11-07T12:00:00+00:00","first_seen_at":null,"has_file":false,"link_path":"/dashboard/library/low-fodmap","has_preview":false,"from_name":null},
     {"id":"r4","kind":"care_plan","title":"Phase 1","sent_at":"2026-10-18T09:00:00+00:00","first_seen_at":null,"has_file":false,"link_path":"/dashboard/plan","has_preview":false,"from_name":"Alessandra"},
     {"id":"r5","kind":"invoice","title":"Invoice FA-2026-098","sent_at":"2026-10-02T09:00:00+00:00","first_seen_at":null,"has_file":true,"link_path":null,"has_preview":false,"from_name":"Thomas"},
     {"id":"r6","kind":"some_future_kind","title":"Odd","sent_at":null,"first_seen_at":null,"has_file":false,"link_path":null,"has_preview":false,"from_name":null}
    ]
    """

    func docs() throws -> [MemberDocument] { try JSON.decode([MemberDocument].self, from: Data(Self.json.utf8)) }

    @Test func decodesTheFunctionRows() throws {
        let d = try docs()
        #expect(d.count == 6)
        #expect(d[0].kind == .labReport && d[0].hasFile && d[0].hasPreview && d[0].sentAt != nil)
        #expect(d[0].isNew && !d[1].isNew)
        #expect(d[2].linkPath == "/dashboard/library/low-fodmap" && !d[2].hasFile)
        #expect(d[5].kind == .file, "an unknown kind is a plain file, not a decoding failure")
    }

    @Test func eachKindHasItsOwnColourAndName() {
        #expect(Set(DocumentKind.allCases.map(\.tintHex)).count == DocumentKind.allCases.count)
        #expect(DocumentKind.labReport.tintHex == 0x6B3F8A && DocumentKind.report.tintHex == 0x2E5438)
        #expect(DocumentKind.allCases.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
    }

    @Test func filtersAndSortsNewestFirst() throws {
        let d = try docs()
        #expect(DocumentsLogic.filtered(d, by: .all).map(\.id) == ["r1", "r3", "r2", "r4", "r5", "r6"], "undated last")
        #expect(DocumentsLogic.filtered(d, by: .reports).map(\.id) == ["r2"])
        #expect(DocumentsLogic.filtered(d, by: .labReports).map(\.id) == ["r1"])
        #expect(DocumentsLogic.filtered(d, by: .resources).map(\.id) == ["r3"])
        #expect(DocumentsLogic.filtered(d, by: .invoices).map(\.id) == ["r5"])
        #expect(DocumentsLogic.unseenCount(d) == 5)
    }

    @Test func linksOnlyOpenOnTheMembersSite() {
        #expect(DocumentsLogic.webURL(linkPath: "/dashboard/plan")?.absoluteString == "https://members.functionalps.ch/dashboard/plan")
        #expect(DocumentsLogic.webURL(linkPath: "https://members.functionalps.ch/x")?.host == "members.functionalps.ch")
        #expect(DocumentsLogic.webURL(linkPath: "https://evil.example/x") == nil)
        #expect(DocumentsLogic.webURL(linkPath: "//evil.example/x") == nil)
        #expect(DocumentsLogic.webURL(linkPath: "http://members.functionalps.ch/x") == nil)
        #expect(DocumentsLogic.webURL(linkPath: nil) == nil && DocumentsLogic.webURL(linkPath: " ") == nil)
    }

    @Test func aTapResolvesFromTheDocumentAndItsFileRow() throws {
        let d = try docs()
        let file = DocumentFile(storageBucket: "document-releases", storagePath: "p/r1.pdf")
        #expect(DocumentsLogic.plan(for: d[0], file: file) == .sign(bucket: "document-releases", path: "p/r1.pdf"))
        #expect(DocumentsLogic.plan(for: d[0], file: DocumentFile(storageBucket: "somewhere-else", storagePath: "x.pdf")) == .unavailable)
        #expect(DocumentsLogic.plan(for: d[0], file: nil) == .unavailable)
        #expect(DocumentsLogic.plan(for: d[3], file: nil) == .destination(.plan))
        guard case .destination(.browser(let url)) = DocumentsLogic.plan(for: d[2], file: DocumentFile(linkPath: "/dashboard/library/low-fodmap")) else {
            Issue.record("a link resource opens in the browser"); return
        }
        #expect(url.path == "/dashboard/library/low-fodmap")
    }

    @Test func fileRowDecodesAsAnArrayOrAnObject() throws {
        let arr = #"[{"storage_bucket":"document-releases","storage_path":"p/r.pdf","link_path":null,"preview_path":"p/r.png"}]"#
        let obj = #"{"storage_bucket":"invoices","storage_path":"p/i.pdf","link_path":null,"preview_path":null}"#
        #expect(try DocumentFile.decode(Data(arr.utf8))?.previewPath == "p/r.png")
        #expect(try DocumentFile.decode(Data(obj.utf8))?.storageBucket == "invoices")
        #expect(try DocumentFile.decode(Data("[]".utf8)) == nil)
        #expect(try DocumentFile.decode(Data("null".utf8)) == nil)
    }

    @Test func subtitleIsDateThenFirstName() throws {
        let d = try docs()
        let s = DocumentsLogic.subtitle(d[0])
        #expect(s.hasSuffix(" · Thomas") && s.contains("2026"))
        #expect(DocumentsLogic.subtitle(d[5]).isEmpty)
    }
}
