import Foundation
import Observation

/// The Documents screen's state: which filter is on, which document is opening, what is presented, and
/// what to say when a document cannot be opened. View → ViewModel → Service (rule 1).
@MainActor
@Observable
final class DocumentsViewModel {
    /// A page or file to show in the in-app browser.
    struct Page: Identifiable, Equatable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var filter: DocumentFilter = .all
    private(set) var openingId: String?
    var page: Page?
    /// Set when a tap resolves to the app's own plan page; the view pushes it and clears it.
    var showPlan = false
    private(set) var openError: AppError?

    private let service: DocumentsService

    init(service: DocumentsService) { self.service = service }

    var state: Loadable<[MemberDocument]> { service.state }

    /// The list for the current filter, newest first. Empty while a filter matches nothing (own empty state).
    var visible: [MemberDocument] { DocumentsLogic.filtered(service.documents, by: filter) }

    /// Counts the filters can show; `nil`-free so the strip never reflows.
    func count(for filter: DocumentFilter) -> Int { service.documents.filter { filter.includes($0.kind) }.count }

    var unseen: Int { DocumentsLogic.unseenCount(service.documents) }

    func load(force: Bool = false) async { await service.load(force: force) }

    func dismissError() { openError = nil }

    /// Opens a document: resolves it, presents it, then records the open (never before it showed).
    func open(_ doc: MemberDocument) async {
        guard openingId == nil else { return }
        openingId = doc.id
        openError = nil
        defer { openingId = nil }
        do {
            switch try await service.resolve(doc) {
            case .browser(let url): page = Page(url: url)
            case .plan: showPlan = true
            }
            await service.markSeen(doc)
        } catch let error as AppError {
            openError = error
        } catch {
            openError = .unknown(detail: String(describing: error))
        }
    }
}
