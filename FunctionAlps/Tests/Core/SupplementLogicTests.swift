import Foundation
import Testing
@testable import FunctionAlps

@Suite("Supplement library (the CLINICAL publisher's contract, decoded and ordered)")
struct SupplementLogicTests {
    // MARK: Fixtures — exactly what `member_library_get` / `member_library_list` return

    static let pageJSON = """
    {"title":"Magnesium","tags":["supplement","pillar:nutrition"],"body_md":"# Magnesium","locked":false,"template":"supplement",
     "structured":{"supplement_page":{"v":1,"dossier":{"id":"d1","version":3},"name":"Magnesium","slug":"magnesium","category":"Mineral","line":"A mineral.",
       "visual":{"kind":"element","elements":[{"symbol":"Mg","number":12,"name":"Magnesium","mass":24.305}]},
       "benefits":[{"text":"Fewer attacks","sources":[4],"use":"migraine"},{"text":"Sooner asleep","sources":[1],"use":"sleep"},{"bad":true}],
       "physiology":{"role":[{"text":"Enzymes","sources":[9]}],"stored":[],"absorbed":[{"text":"Gut","sources":[9]}],"lowered_by":[]},
       "uses":[{"key":"sleep","slug":"magnesium-for-sleep","title":"Magnesium for sleep","pillar":"sommeil","evidence":{"level":"limited","line":"3 trials","basis":[1]},"summary":"small"},
               {"key":"cramps","slug":"magnesium-for-cramps","title":"Magnesium for muscle cramps","pillar":"mouvement","evidence":{"level":"not_supported","line":null,"basis":[3]},"summary":null},
               {"key":"migraine","slug":"magnesium-for-migraine","title":"Magnesium for migraine","pillar":"stress","evidence":{"level":"moderate","line":"10 trials","basis":[4]},"summary":"fewer"},
               {"key":"future","slug":"magnesium-for-future","title":"Future","pillar":null,"evidence":{"level":"astonishing","line":null,"basis":[]},"summary":null}],
       "label":[{"text":"Elemental amount","sources":[9]}],"ask_first":[{"text":"Kidney problems","sources":[9]},{"text":"Pregnant","sources":["P"]}],
       "side_effects":[{"text":"Loose stools","sources":[3]}],"upper_limits":[{"text":"250 mg a day","sources":[8]}],
       "food":[{"name":"Pumpkin seeds","portion":"30 g","amount_mg":150},{"name":"Almonds","portion":null,"amount_mg":null}],
       "habits":["11111111-1111-1111-1111-111111111111"],"articles":["evening-routine"],
       "sources":[{"n":1,"kind":"systematic review","label":"Mah & Pitre 2021","pmid":"33865376"},{"n":3,"kind":"Cochrane review","label":"Garrison 2020","doi":"10.1002/14651858.CD009402.pub3"},
                  {"n":4,"kind":"meta-analysis","label":"Chiu 2016","pmid":26752497},{"n":8,"kind":"authority","label":"EFSA","url":"https://www.efsa.europa.eu/x"},{"n":9,"kind":"authority","label":"NIH ODS","url":"javascript:alert(1)"},{"n":"P","kind":"practice rule","label":"Our practice rule"}]}}}
    """

    static let useJSON = """
    {"title":"Magnesium for muscle cramps","tags":["supplement","supplement-use","supplement-of:magnesium","pillar:mouvement"],"body_md":"# Cramps","locked":false,"template":"supplement",
     "structured":{"supplement_use":{"v":1,"dossier":{"id":"d1","version":3},"supplement":{"name":"Magnesium","slug":"magnesium"},"key":"cramps","title":"Magnesium for muscle cramps","pillar":"mouvement",
       "evidence":{"level":"not_supported","line":"No better than placebo.","basis":[3]},"benefits":[],"forms":[],"dose":null,"timing":null,"onset":null,"label":[],"ask_first":[],
       "habits":[],"articles":[],"sources":[{"n":3,"kind":"Cochrane review","label":"Garrison 2020","pmid":"32956536"}]}}}
    """

    static let unknownVersionJSON = """
    {"title":"Magnesium","tags":["supplement"],"body_md":"# Magnesium","locked":false,"template":"supplement",
     "structured":{"supplement_page":{"v":2,"name":"Magnesium","slug":"magnesium","something":"new"}}}
    """

    private func row(_ json: String) throws -> LibraryGetRow {
        try JSON.decoder.decode(LibraryGetRow.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    @Test func decodesAPage() throws {
        let row = try self.row(Self.pageJSON)
        #expect(row.template == "supplement")
        #expect(row.bodyMd == "# Magnesium")
        let page = try #require(row.supplementPage)
        #expect(row.supplementUse == nil)
        #expect(page.name == "Magnesium" && page.category == "Mineral" && page.dossier?.version == 3)
        #expect(page.visual == .elements([SupplementVisual.Element(symbol: "Mg", number: 12, name: "Magnesium", mass: "24.305")]))
        // A malformed item drops; the list survives.
        #expect(page.benefits.map(\.text) == ["Fewer attacks", "Sooner asleep"])
        #expect(page.benefits[0].use == "migraine" && page.benefits[0].sources == [SourceKey(4)])
        #expect(page.physiology.role.first?.text == "Enzymes" && page.physiology.stored.isEmpty)
        // An evidence level this build does not know drops that use, never the page.
        #expect(page.uses.map(\.key) == ["sleep", "cramps", "migraine"])
        #expect(page.uses[1].evidence.level == .notSupported && page.uses[1].summary == nil)
        #expect(page.askFirst[1].sources == [SourceKey("P")])
        #expect(page.food[0].amountMg == 150 && page.food[1].portion == nil)
        #expect(page.habits == ["11111111-1111-1111-1111-111111111111"] && page.articles == ["evening-routine"])
        #expect(page.sources.map(\.n.raw) == ["1", "3", "4", "8", "9", "P"])
        #expect(page.sources[2].pmid == "26752497")
    }

    @Test func sourceLinksFollowOnlySafeTargets() throws {
        let page = try #require(self.row(Self.pageJSON).supplementPage)
        #expect(page.sources[0].link?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/33865376/")
        #expect(page.sources[1].link?.absoluteString == "https://doi.org/10.1002/14651858.CD009402.pub3")
        #expect(page.sources[3].link?.absoluteString == "https://www.efsa.europa.eu/x")
        #expect(page.sources[4].link == nil)   // javascript: is not a page
        #expect(page.sources[5].link == nil)   // a practice rule has nothing to open
        #expect(SupplementLogic.cited([SourceKey(4), SourceKey(42), SourceKey("P")], in: page.sources).map(\.id) == ["4", "P"])
    }

    @Test func decodesAUse() throws {
        let row = try self.row(Self.useJSON)
        let use = try #require(row.supplementUse)
        #expect(row.supplementPage == nil)
        #expect(use.supplement.slug == "magnesium" && use.key == "cramps")
        #expect(use.evidence.level == .notSupported && use.evidence.line == "No better than placebo." && use.evidence.basis == [SourceKey(3)])
        #expect(use.dose == nil && use.timing == nil && use.onset == nil)
        #expect(!SupplementLogic.carriesDose(use.evidence.level))
        #expect(SupplementLogic.carriesDose(.limited) && SupplementLogic.carriesDose(.strong) && !SupplementLogic.carriesDose(.weak))
    }

    @Test func unknownVersionOrMissingPayloadFallsBackToTheReader() throws {
        let newer = try self.row(Self.unknownVersionJSON)
        #expect(newer.template == "supplement" && newer.supplementPage == nil && newer.supplementUse == nil)
        #expect(SupplementLogic.presentation(newer) == .reader)
        #expect(newer.bodyMd == "# Magnesium")   // the reader still has something to show

        let plain = LibraryGetRow(title: "Walking", tags: ["pillar:intestin"], bodyMd: "body", locked: false)
        #expect(SupplementLogic.presentation(plain) == .reader)
        #expect(SupplementLogic.presentation(nil) == .reader)

        let noPayload = LibraryGetRow(title: "Mg", tags: ["supplement"], bodyMd: "body", locked: false, template: "supplement")
        #expect(SupplementLogic.presentation(noPayload) == .reader)
        if case .reader(let result) = SupplementLogic.open(slug: "magnesium", bundle: nil, row: noPayload) {
            #expect(result?.supplement == true && result?.bodyMd == "body")
        } else {
            Issue.record("expected the reader")
        }
    }

    @Test func openBuildsAnEntryWithLockAndVeil() throws {
        let page = try #require(self.row(Self.pageJSON).supplementPage)
        let openRow = LibraryGetRow(title: "Magnesium", tags: ["supplement"], bodyMd: nil, locked: false, template: "supplement", supplementPage: page)
        guard case .supplement(let entry) = SupplementLogic.open(slug: "magnesium", bundle: LibraryDemo.bundle, row: openRow) else {
            Issue.record("expected a supplement entry"); return
        }
        #expect(entry.content == .page(page) && !entry.locked && !entry.veiled && entry.title == "Magnesium")

        let lockedRow = LibraryGetRow(title: nil, tags: ["supplement"], bodyMd: nil, locked: true, template: "supplement", supplementPage: page)
        guard case .supplement(let locked) = SupplementLogic.open(slug: "magnesium", bundle: nil, row: lockedRow) else {
            Issue.record("expected a supplement entry"); return
        }
        #expect(locked.locked && locked.lockReason == .programme && locked.veiled && locked.title == "Magnesium")   // no bundle → veil fails closed
    }

    @Test func listRowReadsTheVisualWithoutThePage() throws {
        let json = """
        [{"slug":"creatine","title":"Creatine","summary":"Strength.","published_at":null,"tags":["supplement"],"is_locked":false,
          "appearance":{"cover_url":"https://x/c.png","supplement_visual":{"kind":"molecule","cid":586,"name":"Creatine","formula":"C4H9N3O2",
            "atoms":[["C",0,0.5],["N",0.866,0],["O",1.7,0.2]],"bonds":[[0,1,1],[1,2,2],[1,9,1]]}}},
         {"slug":"zinc","title":"Zinc","summary":null,"published_at":null,"tags":["supplement"],"is_locked":true,
          "appearance":{"cover_url":"https://x/z.png","supplement_visual":{"kind":"hologram"}}},
         {"slug":"plain","title":"Plain","summary":null,"published_at":null,"tags":[],"is_locked":false,"appearance":null}]
        """
        let rows = try JSON.decoder.decode([LibraryListRow].self, from: Data(json.utf8))
        guard case .molecule(let m) = try #require(rows[0].supplementVisual) else { Issue.record("expected a molecule"); return }
        #expect(m.cid == 586 && m.atoms.count == 3 && m.atoms[1] == SupplementVisual.Atom(element: "N", x: 0.866, y: 0))
        #expect(m.bonds == [SupplementVisual.Bond(a: 0, b: 1, order: 1), SupplementVisual.Bond(a: 1, b: 2, order: 2)])   // a bond off the list drops
        #expect(rows[0].coverUrl == "https://x/c.png")
        // An unknown visual kind drops the visual and keeps the cover.
        #expect(rows[1].supplementVisual == nil && rows[1].coverUrl == "https://x/z.png" && rows[1].isLocked == true)
        #expect(rows[2].supplementVisual == nil && rows[2].coverUrl == nil)
    }

    // MARK: Grouping (list vs uses, out of Foundations)

    @Test func usesGroupUnderTheirPageAndStayOutOfEverySection() throws {
        var raw = LibraryRaw()
        raw.tracks = [LibraryRawTrack(id: "t1", slug: "gut", title: "Gut", description: nil, pillar: "intestin", coverStyle: nil, position: 1, requiresStage: nil, requiresTrackId: nil)]
        raw.list = [
            LibraryListRow(slug: "walking", title: "Walking", summary: nil, publishedAt: nil, tags: ["pillar:intestin"], isLocked: false, coverUrl: nil),
            LibraryListRow(slug: "magnesium", title: "Magnesium", summary: "A mineral.", publishedAt: nil, tags: ["supplement", "pillar:nutrition"], isLocked: false, coverUrl: nil,
                           supplementVisual: SupplementSample.magnesiumVisual),
            LibraryListRow(slug: "magnesium-for-sleep", title: "Magnesium for sleep", summary: nil, publishedAt: nil, tags: ["supplement", "supplement-use", "supplement-of:magnesium", "pillar:sommeil"], isLocked: false, coverUrl: nil),
            LibraryListRow(slug: "magnesium-for-migraine", title: "Magnesium for migraine", summary: nil, publishedAt: nil, tags: ["supplement-use", "supplement-of: magnesium "], isLocked: false, coverUrl: nil),
            LibraryListRow(slug: "orphan-use", title: "Orphan", summary: nil, publishedAt: nil, tags: ["supplement", "supplement-use"], isLocked: false, coverUrl: nil),
            LibraryListRow(slug: "creatine", title: "Creatine", summary: nil, publishedAt: nil, tags: ["supplement"], isLocked: true, coverUrl: nil),
        ]
        let bundle = try #require(LibraryLogic.assemble(raw, stage: .active))
        let foundations = bundle.resources.filter { !$0.supplement }
        #expect(foundations.map(\.slug) == ["walking"])   // no use row (even one tagged only `supplement-use`) reaches Foundations
        #expect(SupplementLogic.pages(bundle.resources).map(\.slug) == ["magnesium", "creatine"])
        let uses = SupplementLogic.usesByPage(bundle.resources)
        #expect(uses["magnesium"]?.map(\.slug) == ["magnesium-for-sleep", "magnesium-for-migraine"])
        #expect(uses.count == 1)   // the orphan belongs nowhere
        #expect(SupplementLogic.uses(of: "creatine", in: bundle.resources).isEmpty)
        let mg = try #require(bundle.resources.first { $0.slug == "magnesium" })
        #expect(mg.supplementVisual == SupplementSample.magnesiumVisual && !mg.supplementUse && mg.supplementOf == nil)
        let sleep = try #require(bundle.resources.first { $0.slug == "magnesium-for-sleep" })
        #expect(sleep.supplementUse && sleep.supplementOf == "magnesium" && sleep.supplement && sleep.pillar == "sommeil")
    }

    @Test func tagsAndChips() {
        #expect(SupplementLogic.isUse(tags: ["supplement", "supplement-use"]))
        #expect(!SupplementLogic.isUse(tags: ["supplement"]) && !SupplementLogic.isUse(tags: nil))
        #expect(SupplementLogic.pageSlug(fromTags: ["supplement-of:magnesium"]) == "magnesium")
        #expect(SupplementLogic.pageSlug(fromTags: ["supplement-of:"]) == nil && SupplementLogic.pageSlug(fromTags: nil) == nil)
        #expect(SupplementLogic.useChip(title: "Magnesium for sleep", supplement: "Magnesium") == "Sleep")
        #expect(SupplementLogic.useChip(title: "Magnesium for stress and anxiety", supplement: "magnesium") == "Stress and anxiety")
        #expect(SupplementLogic.useChip(title: "Better nights", supplement: "Magnesium") == "Better nights")
        #expect(SupplementLogic.useChip(title: "Magnesium for ", supplement: "Magnesium") == "Magnesium for")
    }

    // MARK: Ordering and the evidence scale

    @Test func usesOrderByEvidenceStrongestFirstKeepingTies() throws {
        let page = try #require(self.row(Self.pageJSON).supplementPage)
        #expect(SupplementLogic.ordered(page.uses).map(\.key) == ["migraine", "sleep", "cramps"])
        let tie = [
            SupplementPage.UseRef(key: "b", slug: "b", title: "B", evidence: SupplementEvidence(level: .limited)),
            SupplementPage.UseRef(key: "a", slug: "a", title: "A", evidence: SupplementEvidence(level: .limited)),
            SupplementPage.UseRef(key: "s", slug: "s", title: "S", evidence: SupplementEvidence(level: .strong)),
            SupplementPage.UseRef(key: "w", slug: "w", title: "W", evidence: SupplementEvidence(level: .weak)),
        ]
        #expect(SupplementLogic.ordered(tie).map(\.key) == ["s", "b", "a", "w"])
    }

    @Test func evidenceLevelsAreWordsAndDots() {
        #expect(EvidenceLevel.allCases.map(\.rank) == [4, 3, 2, 1, 0])
        #expect(EvidenceLevel.strong.dots == 4 && EvidenceLevel.moderate.dots == 3 && EvidenceLevel.limited.dots == 2 && EvidenceLevel.weak.dots == 1)
        #expect(EvidenceLevel.notSupported.dots == nil)   // the dash
        #expect(EvidenceLevel.strong.label == "Strong evidence")
        #expect(EvidenceLevel.notSupported.label == "Not supported")
        #expect(EvidenceLevel(rawValue: "not_supported") == .notSupported && EvidenceLevel(rawValue: "notSupported") == nil)
    }

    @Test func sourceBadgesHaveASymbolForNumbersAndLetters() {
        #expect(SourceBadge.symbolName("4") == "4.circle.fill")
        #expect(SourceBadge.symbolName("50") == "50.circle.fill" && SourceBadge.symbolName("51") == nil)
        #expect(SourceBadge.symbolName("P") == "p.circle.fill" && SourceBadge.symbolName("PP") == nil && SourceBadge.symbolName("0") == nil)
    }

    // MARK: The labelled sample and the articles

    @Test func theSampleOpensOffline() throws {
        guard case .supplement(let page) = LibraryDemo.open(slug: "demo-magnesium"), case .page(let mg) = page.content else {
            Issue.record("expected the magnesium page"); return
        }
        #expect(mg.uses.count == 5 && mg.sources.count == 10 && !page.veiled)
        for use in mg.uses {
            guard case .supplement(let entry) = LibraryDemo.open(slug: use.slug), case .use(let u) = entry.content else {
                Issue.record("expected the use \(use.slug)"); continue
            }
            #expect(u.key == use.key && u.supplement.slug == "demo-magnesium")
            if !SupplementLogic.carriesDose(u.evidence.level) { #expect(u.dose == nil) }
        }
        guard case .supplement(let creatine) = LibraryDemo.open(slug: "demo-creatine"), case .page(let cr) = creatine.content, case .molecule(let m) = cr.visual else {
            Issue.record("expected the creatine molecule"); return
        }
        #expect(m.atoms.count == 9 && m.bonds.count == 8)
        #expect(SupplementLogic.pages(LibraryDemo.resources).map(\.slug) == ["demo-magnesium", "demo-creatine"])
        #expect(SupplementLogic.usesByPage(LibraryDemo.resources)["demo-magnesium"]?.count == 5)
        if case .reader(let r) = LibraryDemo.open(slug: "demo-nsdr") { #expect(r?.title == "NSDR / Yoga Nidra") } else { Issue.record("expected the reader") }
        #expect(LibraryDemo.reader(slug: "demo-omega-3") == nil)
    }

    @Test func articlesResolveFromTheBundle() {
        let refs = SupplementLogic.articles(["demo-sleep-repair-2", "demo-nsdr", "unknown-slug"], in: LibraryDemo.bundle)
        #expect(refs.map(\.title) == ["The evening ramp", "NSDR / Yoga Nidra", "Unknown slug"])
        #expect(refs[0].track == "Sleep Repair" && refs[1].track == nil)
    }

    @Test func moleculeFitsItsFrameAndFlipsY() {
        let atoms = [SupplementVisual.Atom(element: "C", x: 0, y: 0), SupplementVisual.Atom(element: "N", x: 2, y: 1)]
        let points = MoleculeView.fit(atoms, in: CGSize(width: 120, height: 82), inset: 10)
        #expect(points.count == 2)
        #expect(points[0].x == 10 && points[1].x == 110)          // the wider axis spans the frame
        #expect(points[0].y > points[1].y)                        // PubChem y up → screen y down
        #expect(MoleculeView.fit([], in: CGSize(width: 1, height: 1), inset: 0).isEmpty)
    }
}
