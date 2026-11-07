import Foundation

// The supplement library as CLINICAL publishes it (docs/foundation-cards/SUPPLEMENT_LIBRARY.md): a page
// (`structured.supplement_page` v1) and one page per use (`structured.supplement_use` v1) on `supplement`-template
// library rows, plus `appearance.supplement_visual` on the list row. Every word a member reads here is in the
// payload Thomas approved; the app decodes it, orders it and draws it. Decoding is lenient — a malformed item
// drops, an unknown version or payload drops to the reader on `body_md` — so an older build never breaks on a
// newer page. Keys arrive snake_case and are read through `JSON.decoder` (convertFromSnakeCase).

/// The five levels of the evidence scale, as the publisher writes them.
enum EvidenceLevel: String, Decodable, Sendable, Equatable, CaseIterable {
    case strong, moderate, limited, weak
    case notSupported = "not_supported"
}

/// A source number as the payload writes it (`n`): usually an integer, sometimes a letter ("P", a practice rule).
struct SourceKey: Hashable, Sendable, Decodable, Identifiable {
    let raw: String
    var id: String { raw }

    init(_ raw: String) { self.raw = raw }
    init(_ n: Int) { raw = String(n) }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { raw = String(n) } else { raw = try c.decode(String.self) }
    }
}

/// One line of the payload with its source numbers; a benefit also names its use (`uses[].key`).
struct SupplementItem: Decodable, Sendable, Equatable {
    let text: String
    var sources: [SourceKey] = []
    var use: String? = nil

    init(text: String, sources: [SourceKey] = [], use: String? = nil) {
        self.text = text; self.sources = sources; self.use = use
    }

    private enum CodingKeys: String, CodingKey { case text, sources, use }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        sources = (try? c.decodeIfPresent([SourceKey].self, forKey: .sources)) ?? []
        use = try? c.decodeIfPresent(String.self, forKey: .use)
    }
}

/// A numbered source: a study (pmid / doi), an authority page (url) or a practice rule (label only).
struct SourceRef: Decodable, Sendable, Equatable, Identifiable {
    let n: SourceKey
    let kind: String?
    let label: String
    let pmid: String?
    let doi: String?
    let url: String?
    var id: String { n.raw }

    init(n: SourceKey, kind: String? = nil, label: String, pmid: String? = nil, doi: String? = nil, url: String? = nil) {
        self.n = n; self.kind = kind; self.label = label; self.pmid = pmid; self.doi = doi; self.url = url
    }

    private enum CodingKeys: String, CodingKey { case n, kind, label, pmid, doi, url }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = try c.decode(SourceKey.self, forKey: .n)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        pmid = (try? c.decodeIfPresent(SourceKey.self, forKey: .pmid))?.raw
        doi = try? c.decodeIfPresent(String.self, forKey: .doi)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
    }

    /// Where "Open" goes: the page itself, else the DOI, else PubMed. Only http(s) is followed.
    var link: URL? {
        if let url = LibraryLogic.coverURL(url) { return url }
        if let doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        if let pmid, !pmid.isEmpty { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
        return nil
    }
}

/// The evidence behind a use: the level, one line on what the studies were, and the sources it rests on.
struct SupplementEvidence: Decodable, Sendable, Equatable {
    let level: EvidenceLevel
    var line: String? = nil
    var basis: [SourceKey] = []

    init(level: EvidenceLevel, line: String? = nil, basis: [SourceKey] = []) {
        self.level = level; self.line = line; self.basis = basis
    }

    private enum CodingKeys: String, CodingKey { case level, line, basis }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(EvidenceLevel.self, forKey: .level)
        line = try? c.decodeIfPresent(String.self, forKey: .line)
        basis = (try? c.decodeIfPresent([SourceKey].self, forKey: .basis)) ?? []
    }
}

/// The scientific visual: one periodic-table tile per element (a mineral, a blend), or a molecule drawn from
/// PubChem's 2D coordinates (atoms `[element, x, y]`, bonds `[a, b, order]`, 0-based).
enum SupplementVisual: Sendable, Equatable, Decodable {
    case elements([Element])
    case molecule(Molecule)

    struct Element: Sendable, Equatable, Decodable {
        let symbol: String
        let number: Int
        let name: String
        /// Kept as text: the app formats nothing, it prints what the publisher wrote.
        let mass: String?

        init(symbol: String, number: Int, name: String, mass: String?) {
            self.symbol = symbol; self.number = number; self.name = name; self.mass = mass
        }

        private enum CodingKeys: String, CodingKey { case symbol, number, name, mass }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try c.decode(String.self, forKey: .symbol)
            number = try c.decode(Int.self, forKey: .number)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? symbol
            if let text = try? c.decodeIfPresent(String.self, forKey: .mass) {
                mass = text
            } else if let value = try? c.decodeIfPresent(Double.self, forKey: .mass) {
                mass = String(value)
            } else {
                mass = nil
            }
        }
    }

    struct Atom: Sendable, Equatable, Decodable {
        let element: String
        let x: Double
        let y: Double

        init(element: String, x: Double, y: Double) { self.element = element; self.x = x; self.y = y }

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            element = try c.decode(String.self)
            x = try c.decode(Double.self)
            y = try c.decode(Double.self)
        }
    }

    struct Bond: Sendable, Equatable, Decodable {
        let a: Int
        let b: Int
        let order: Int

        init(a: Int, b: Int, order: Int) { self.a = a; self.b = b; self.order = order }

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            a = try c.decode(Int.self)
            b = try c.decode(Int.self)
            order = c.isAtEnd ? 1 : ((try? c.decode(Int.self)) ?? 1)
        }
    }

    struct Molecule: Sendable, Equatable, Decodable {
        let cid: Int?
        let name: String?
        let formula: String?
        let atoms: [Atom]
        let bonds: [Bond]

        init(cid: Int?, name: String?, formula: String?, atoms: [Atom], bonds: [Bond]) {
            self.cid = cid; self.name = name; self.formula = formula; self.atoms = atoms; self.bonds = bonds
        }

        private enum CodingKeys: String, CodingKey { case cid, name, formula, atoms, bonds }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cid = try? c.decodeIfPresent(Int.self, forKey: .cid)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            formula = try? c.decodeIfPresent(String.self, forKey: .formula)
            let decodedAtoms = try c.decode([Atom].self, forKey: .atoms)
            if decodedAtoms.isEmpty { throw DecodingError.dataCorruptedError(forKey: .atoms, in: c, debugDescription: "no atoms") }
            // A bond that names an atom the list does not have is dropped, never drawn off the canvas.
            let count = decodedAtoms.count
            let decodedBonds = Lenient<Bond>.array(try c.decode([Lenient<Bond>].self, forKey: .bonds))
            atoms = decodedAtoms
            bonds = decodedBonds.filter { $0.a >= 0 && $0.b >= 0 && $0.a < count && $0.b < count }
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, elements }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "element":
            let elements = Lenient<Element>.array(try c.decode([Lenient<Element>].self, forKey: .elements))
            if elements.isEmpty { throw DecodingError.dataCorruptedError(forKey: .elements, in: c, debugDescription: "no elements") }
            self = .elements(elements)
        case "molecule":
            self = .molecule(try Molecule(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown visual kind \(other)")
        }
    }
}

/// `structured.supplement_page` v1.
struct SupplementPage: Decodable, Sendable, Equatable {
    static let version = 1

    struct Dossier: Decodable, Sendable, Equatable { let id: String?; let version: Int? }

    struct Physiology: Decodable, Sendable, Equatable {
        var role: [SupplementItem] = []
        var stored: [SupplementItem] = []
        var absorbed: [SupplementItem] = []
        var loweredBy: [SupplementItem] = []

        init(role: [SupplementItem] = [], stored: [SupplementItem] = [], absorbed: [SupplementItem] = [], loweredBy: [SupplementItem] = []) {
            self.role = role; self.stored = stored; self.absorbed = absorbed; self.loweredBy = loweredBy
        }

        private enum CodingKeys: String, CodingKey { case role, stored, absorbed, loweredBy }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = Lenient<SupplementItem>.list(c, .role)
            stored = Lenient<SupplementItem>.list(c, .stored)
            absorbed = Lenient<SupplementItem>.list(c, .absorbed)
            loweredBy = Lenient<SupplementItem>.list(c, .loweredBy)
        }

        var isEmpty: Bool { role.isEmpty && stored.isEmpty && absorbed.isEmpty && loweredBy.isEmpty }
    }

    /// A use as the page lists it — the row that opens the use's own page.
    struct UseRef: Decodable, Sendable, Equatable, Identifiable {
        let key: String
        let slug: String
        let title: String
        let pillar: String?
        let evidence: SupplementEvidence
        let summary: String?
        var id: String { slug }

        init(key: String, slug: String, title: String, pillar: String? = nil, evidence: SupplementEvidence, summary: String? = nil) {
            self.key = key; self.slug = slug; self.title = title; self.pillar = pillar; self.evidence = evidence; self.summary = summary
        }

        private enum CodingKeys: String, CodingKey { case key, slug, title, pillar, evidence, summary }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            slug = try c.decode(String.self, forKey: .slug)
            title = try c.decode(String.self, forKey: .title)
            pillar = try? c.decodeIfPresent(String.self, forKey: .pillar)
            evidence = try c.decode(SupplementEvidence.self, forKey: .evidence)
            summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        }
    }

    struct Food: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        let portion: String?
        let amountMg: Double?
        var id: String { name }

        init(name: String, portion: String? = nil, amountMg: Double? = nil) { self.name = name; self.portion = portion; self.amountMg = amountMg }

        private enum CodingKeys: String, CodingKey { case name, portion, amountMg }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            portion = try? c.decodeIfPresent(String.self, forKey: .portion)
            amountMg = try? c.decodeIfPresent(Double.self, forKey: .amountMg)
        }
    }

    let v: Int
    let dossier: Dossier?
    let name: String
    let slug: String
    let category: String?
    let line: String?
    let visual: SupplementVisual?
    let benefits: [SupplementItem]
    let physiology: Physiology
    let uses: [UseRef]
    let label: [SupplementItem]
    let askFirst: [SupplementItem]
    let sideEffects: [SupplementItem]
    let upperLimits: [SupplementItem]
    let food: [Food]
    /// `habit_bank` ids ("Goes with"), resolved against the action bank the app already reads.
    let habits: [String]
    /// Library slugs, resolved from the bundle.
    let articles: [String]
    let sources: [SourceRef]

    init(v: Int = SupplementPage.version, dossier: Dossier? = nil, name: String, slug: String, category: String? = nil, line: String? = nil,
         visual: SupplementVisual? = nil, benefits: [SupplementItem] = [], physiology: Physiology = Physiology(), uses: [UseRef] = [],
         label: [SupplementItem] = [], askFirst: [SupplementItem] = [], sideEffects: [SupplementItem] = [], upperLimits: [SupplementItem] = [],
         food: [Food] = [], habits: [String] = [], articles: [String] = [], sources: [SourceRef] = []) {
        self.v = v; self.dossier = dossier; self.name = name; self.slug = slug; self.category = category; self.line = line
        self.visual = visual; self.benefits = benefits; self.physiology = physiology; self.uses = uses
        self.label = label; self.askFirst = askFirst; self.sideEffects = sideEffects; self.upperLimits = upperLimits
        self.food = food; self.habits = habits; self.articles = articles; self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case v, dossier, name, slug, category, line, visual, benefits, physiology, uses, label, askFirst, sideEffects, upperLimits, food, habits, articles, sources
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        guard v == Self.version else { throw SupplementDecodingError.unsupportedVersion(v) }
        dossier = try? c.decodeIfPresent(Dossier.self, forKey: .dossier)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decode(String.self, forKey: .slug)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        line = try? c.decodeIfPresent(String.self, forKey: .line)
        visual = try? c.decodeIfPresent(SupplementVisual.self, forKey: .visual)
        benefits = Lenient<SupplementItem>.list(c, .benefits)
        physiology = (try? c.decodeIfPresent(Physiology.self, forKey: .physiology)) ?? Physiology()
        uses = Lenient<UseRef>.list(c, .uses)
        label = Lenient<SupplementItem>.list(c, .label)
        askFirst = Lenient<SupplementItem>.list(c, .askFirst)
        sideEffects = Lenient<SupplementItem>.list(c, .sideEffects)
        upperLimits = Lenient<SupplementItem>.list(c, .upperLimits)
        food = Lenient<Food>.list(c, .food)
        habits = (try? c.decodeIfPresent([String].self, forKey: .habits)) ?? []
        articles = (try? c.decodeIfPresent([String].self, forKey: .articles)) ?? []
        sources = Lenient<SourceRef>.list(c, .sources)
    }
}

/// `structured.supplement_use` v1.
struct SupplementUse: Decodable, Sendable, Equatable {
    static let version = 1

    struct Parent: Decodable, Sendable, Equatable {
        let name: String
        let slug: String
    }

    let v: Int
    let dossier: SupplementPage.Dossier?
    let supplement: Parent
    let key: String
    let title: String
    let pillar: String?
    let evidence: SupplementEvidence
    let benefits: [SupplementItem]
    let forms: [SupplementItem]
    /// Null on a weak or not-supported use: no dose, no how-to (the publisher's rule, never the app's).
    let dose: SupplementItem?
    let timing: SupplementItem?
    let onset: SupplementItem?
    let label: [SupplementItem]
    let askFirst: [SupplementItem]
    let habits: [String]
    let articles: [String]
    let sources: [SourceRef]

    init(v: Int = SupplementUse.version, dossier: SupplementPage.Dossier? = nil, supplement: Parent, key: String, title: String, pillar: String? = nil,
         evidence: SupplementEvidence, benefits: [SupplementItem] = [], forms: [SupplementItem] = [], dose: SupplementItem? = nil,
         timing: SupplementItem? = nil, onset: SupplementItem? = nil, label: [SupplementItem] = [], askFirst: [SupplementItem] = [],
         habits: [String] = [], articles: [String] = [], sources: [SourceRef] = []) {
        self.v = v; self.dossier = dossier; self.supplement = supplement; self.key = key; self.title = title; self.pillar = pillar
        self.evidence = evidence; self.benefits = benefits; self.forms = forms; self.dose = dose; self.timing = timing; self.onset = onset
        self.label = label; self.askFirst = askFirst; self.habits = habits; self.articles = articles; self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case v, dossier, supplement, key, title, pillar, evidence, benefits, forms, dose, timing, onset, label, askFirst, habits, articles, sources
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        guard v == Self.version else { throw SupplementDecodingError.unsupportedVersion(v) }
        dossier = try? c.decodeIfPresent(SupplementPage.Dossier.self, forKey: .dossier)
        supplement = try c.decode(Parent.self, forKey: .supplement)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        pillar = try? c.decodeIfPresent(String.self, forKey: .pillar)
        evidence = try c.decode(SupplementEvidence.self, forKey: .evidence)
        benefits = Lenient<SupplementItem>.list(c, .benefits)
        forms = Lenient<SupplementItem>.list(c, .forms)
        dose = try? c.decodeIfPresent(SupplementItem.self, forKey: .dose)
        timing = try? c.decodeIfPresent(SupplementItem.self, forKey: .timing)
        onset = try? c.decodeIfPresent(SupplementItem.self, forKey: .onset)
        label = Lenient<SupplementItem>.list(c, .label)
        askFirst = Lenient<SupplementItem>.list(c, .askFirst)
        habits = (try? c.decodeIfPresent([String].self, forKey: .habits)) ?? []
        articles = (try? c.decodeIfPresent([String].self, forKey: .articles)) ?? []
        sources = Lenient<SourceRef>.list(c, .sources)
    }
}

/// The `structured` column of a `supplement`-template row: whichever payload it carries, each one on its own.
struct SupplementStructured: Decodable, Sendable, Equatable {
    let page: SupplementPage?
    let use: SupplementUse?

    init(page: SupplementPage? = nil, use: SupplementUse? = nil) { self.page = page; self.use = use }

    private enum CodingKeys: String, CodingKey { case supplementPage, supplementUse }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try? c.decodeIfPresent(SupplementPage.self, forKey: .supplementPage)
        use = try? c.decodeIfPresent(SupplementUse.self, forKey: .supplementUse)
    }
}

enum SupplementDecodingError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// One element of a list that may hold a malformed entry: the entry drops, the list survives.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }

    static func array(_ wrapped: [Lenient<T>]) -> [T] { wrapped.compactMap(\.value) }
}


extension Lenient {
    static func list<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [T] {
        array((try? c.decodeIfPresent([Lenient<T>].self, forKey: key)) ?? [])
    }
}
