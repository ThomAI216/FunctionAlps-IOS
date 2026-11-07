import Foundation

/// Pure rules of the supplement library (docs/foundation-cards/SUPPLEMENT_LIBRARY.md). No IO, everything tested:
/// which rows are the list and which are uses, how uses group under their page, how they order, what the evidence
/// scale shows, and when a row falls back to the reader.
enum SupplementLogic {
    static let pageTag = "supplement"
    static let useTag = "supplement-use"
    static let ofPrefix = "supplement-of:"

    // MARK: STUDIO / CLINICAL tag conventions

    /// A use page (`supplement-use`): one use of a supplement, with its own row.
    static func isUse(tags: [String]?) -> Bool { (tags ?? []).contains(useTag) }

    /// The page a use belongs to (`supplement-of:<page slug>`).
    static func pageSlug(fromTags tags: [String]?) -> String? {
        guard let tag = (tags ?? []).first(where: { $0.hasPrefix(ofPrefix) }) else { return nil }
        let slug = tag.dropFirst(ofPrefix.count).trimmingCharacters(in: .whitespaces)
        return slug.isEmpty ? nil : slug
    }

    // MARK: The list

    /// The supplements list: pages only — tagged `supplement`, never `supplement-use`.
    static func pages(_ resources: [LibResource]) -> [LibResource] {
        resources.filter { $0.supplement && !$0.supplementUse }
    }

    /// Use rows under their page slug, in the catalog's order. A use without a page is kept out of every section.
    static func usesByPage(_ resources: [LibResource]) -> [String: [LibResource]] {
        var map: [String: [LibResource]] = [:]
        for r in resources where r.supplementUse {
            guard let page = r.supplementOf else { continue }
            map[page, default: []].append(r)
        }
        return map
    }

    static func uses(of pageSlug: String, in resources: [LibResource]) -> [LibResource] {
        usesByPage(resources)[pageSlug] ?? []
    }

    /// A use as a chip in the list: "Magnesium for sleep" under Magnesium reads "Sleep". Formatting only — the
    /// words are the use's title.
    static func useChip(title: String, supplement: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = supplement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + " for "
        guard !supplement.isEmpty, t.lowercased().hasPrefix(prefix) else { return t }
        let rest = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? t : rest.prefix(1).uppercased() + rest.dropFirst()
    }

    // MARK: Evidence

    /// Uses ranked by evidence, strongest first; ties keep the publisher's order.
    static func ordered(_ uses: [SupplementPage.UseRef]) -> [SupplementPage.UseRef] {
        uses.enumerated()
            .sorted { a, b in
                let ra = a.element.evidence.level.rank, rb = b.element.evidence.level.rank
                return ra != rb ? ra > rb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// A weak or not-supported use carries no dose and no how-to; the publisher sends `dose: null` and the app
    /// never fills the gap.
    static func carriesDose(_ level: EvidenceLevel) -> Bool {
        switch level {
        case .strong, .moderate, .limited: true
        case .weak, .notSupported: false
        }
    }

    // MARK: Opening a row

    /// What a `member_library_get` row opens as: the structured page, a structured use, or the reader on `body_md`
    /// (not a supplement template, no payload, or a payload the build does not know).
    enum Presentation: Sendable, Equatable {
        case page(SupplementPage)
        case use(SupplementUse)
        case reader
    }

    static func presentation(_ row: LibraryGetRow?) -> Presentation {
        guard let row, row.template == pageTag else { return .reader }
        if let page = row.supplementPage { return .page(page) }
        if let use = row.supplementUse { return .use(use) }
        return .reader
    }

    /// The whole open: a structured supplement entry, else the reader's result (`LibraryLogic.reader`).
    static func open(slug: String, bundle: LibraryBundle?, row: LibraryGetRow?) -> LibraryOpen {
        switch presentation(row) {
        case .reader:
            return .reader(LibraryLogic.reader(slug: slug, bundle: bundle, row: row))
        case .page(let page):
            return .supplement(entry(slug: slug, title: row?.title ?? page.name, content: .page(page), bundle: bundle, row: row))
        case .use(let use):
            return .supplement(entry(slug: slug, title: row?.title ?? use.title, content: .use(use), bundle: bundle, row: row))
        }
    }

    private static func entry(slug: String, title: String, content: SupplementEntry.Content, bundle: LibraryBundle?, row: LibraryGetRow?) -> SupplementEntry {
        let locked = row?.locked ?? false
        return SupplementEntry(
            slug: slug,
            title: title,
            content: content,
            locked: locked,
            lockReason: LibraryLogic.lockReason(locked: locked, stage: bundle?.stage),
            // The section veil fails closed, like the list: no bundle, no row → veiled.
            veiled: !(bundle?.access.supplements ?? false),
            bundle: bundle
        )
    }

    // MARK: Articles ("Read" cards)

    struct ArticleRef: Sendable, Equatable, Identifiable {
        let slug: String
        let title: String
        /// The track a lesson belongs to; nil for a standalone resource.
        let track: String?
        var id: String { slug }
    }

    /// Library slugs resolved from the bundle; an unknown slug still opens (its title from the slug).
    static func articles(_ slugs: [String], in bundle: LibraryBundle?) -> [ArticleRef] {
        slugs.map { slug in
            for t in bundle?.tracks ?? [] {
                if let l = t.lessons.first(where: { $0.contentSlug == slug }) { return ArticleRef(slug: slug, title: l.title, track: t.title) }
            }
            if let r = bundle?.resources.first(where: { $0.slug == slug }) { return ArticleRef(slug: slug, title: r.title, track: nil) }
            return ArticleRef(slug: slug, title: LibraryLogic.title(fromSlug: slug), track: nil)
        }
    }

    /// The sources an item cites, in the order of the page's list; a number the list does not have is skipped.
    static func cited(_ keys: [SourceKey], in sources: [SourceRef]) -> [SourceRef] {
        keys.compactMap { key in sources.first { $0.n == key } }
    }
}

extension EvidenceLevel {
    /// Strong first.
    var rank: Int {
        switch self {
        case .strong: 4
        case .moderate: 3
        case .limited: 2
        case .weak: 1
        case .notSupported: 0
        }
    }

    /// Filled dots out of four; nil draws a dash (not supported). Always next to the word, never colour alone.
    var dots: Int? {
        switch self {
        case .strong: 4
        case .moderate: 3
        case .limited: 2
        case .weak: 1
        case .notSupported: nil
        }
    }

    /// The word a member reads (the scale of the design, 2026-11-07).
    var label: String {
        switch self {
        case .strong: String(localized: "supplement.evidence.strong", defaultValue: "Strong evidence")
        case .moderate: String(localized: "supplement.evidence.moderate", defaultValue: "Moderate evidence")
        case .limited: String(localized: "supplement.evidence.limited", defaultValue: "Limited evidence")
        case .weak: String(localized: "supplement.evidence.weak", defaultValue: "Weak evidence")
        case .notSupported: String(localized: "supplement.evidence.notSupported", defaultValue: "Not supported")
        }
    }
}

/// What opens for a library slug: a structured supplement entry, or the reader.
enum LibraryOpen: Sendable, Equatable {
    case reader(ReaderResult?)
    case supplement(SupplementEntry)
}

/// A supplement page or use, with what the screen needs around it.
struct SupplementEntry: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case page(SupplementPage)
        case use(SupplementUse)
    }

    let slug: String
    let title: String
    let content: Content
    /// The row's tier lock (the body is withheld server-side; the page shows the lock note instead).
    let locked: Bool
    let lockReason: LockReason?
    /// `member_library_access.supplements_enabled` is off: the content renders behind the section veil.
    let veiled: Bool
    /// The bundle the entry was opened with — articles and use rows resolve against it.
    let bundle: LibraryBundle?
}
