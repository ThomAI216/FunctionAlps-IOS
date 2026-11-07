import Foundation

/// The supplement library's labelled sample (`LibraryDemo`): the magnesium page, its five uses and the creatine
/// molecule, so the screens land and pass CI before the first supplement is published. The wording is the DRAFT of
/// the design mockup of 2026-11-07 (built from the abstracts cited there), shown only as "Sample preview" when the
/// live reads fail; doses are left unset, as on the mockup. Nothing here is written for a real member.
enum SupplementSample {
    static let pageSlug = "demo-magnesium"

    static let magnesiumVisual: SupplementVisual = .elements([
        SupplementVisual.Element(symbol: "Mg", number: 12, name: "Magnesium", mass: "24.305"),
    ])

    /// Creatine, PubChem CID 586 (C₄H₉N₃O₂): heavy atoms on a 2D lattice, bond length 1.
    static let creatineVisual: SupplementVisual = .molecule(SupplementVisual.Molecule(
        cid: 586, name: "Creatine", formula: "C₄H₉N₃O₂",
        atoms: [
            SupplementVisual.Atom(element: "C", x: 0, y: 0.5),        // 0 methyl
            SupplementVisual.Atom(element: "N", x: 0.866, y: 0),      // 1
            SupplementVisual.Atom(element: "C", x: 1.732, y: 0.5),    // 2 CH2
            SupplementVisual.Atom(element: "C", x: 2.598, y: 0),      // 3 carboxyl C
            SupplementVisual.Atom(element: "O", x: 2.598, y: -1),     // 4 =O
            SupplementVisual.Atom(element: "O", x: 3.464, y: 0.5),    // 5 OH
            SupplementVisual.Atom(element: "C", x: 0.866, y: -1),     // 6 guanidine C
            SupplementVisual.Atom(element: "N", x: 0, y: -1.5),       // 7 =NH
            SupplementVisual.Atom(element: "N", x: 1.732, y: -1.5),   // 8 NH2
        ],
        bonds: [
            SupplementVisual.Bond(a: 0, b: 1, order: 1), SupplementVisual.Bond(a: 1, b: 2, order: 1),
            SupplementVisual.Bond(a: 2, b: 3, order: 1), SupplementVisual.Bond(a: 3, b: 4, order: 2),
            SupplementVisual.Bond(a: 3, b: 5, order: 1), SupplementVisual.Bond(a: 1, b: 6, order: 1),
            SupplementVisual.Bond(a: 6, b: 7, order: 2), SupplementVisual.Bond(a: 6, b: 8, order: 1),
        ]
    ))

    private static func item(_ text: String, _ sources: [String] = [], use: String? = nil) -> SupplementItem {
        SupplementItem(text: text, sources: sources.map(SourceKey.init(_:)), use: use)
    }

    static let sources: [SourceRef] = [
        SourceRef(n: SourceKey(1), kind: "systematic review", label: "Mah & Pitre 2021", pmid: "33865376"),
        SourceRef(n: SourceKey(2), kind: "systematic review", label: "Boyle 2017", pmid: "28445426"),
        SourceRef(n: SourceKey(3), kind: "Cochrane review", label: "Garrison 2020 (Cochrane)", pmid: "32956536"),
        SourceRef(n: SourceKey(4), kind: "meta-analysis", label: "Chiu 2016", pmid: "26752497"),
        SourceRef(n: SourceKey(5), kind: "meta-analysis", label: "Veronese 2016", pmid: "27530471"),
        SourceRef(n: SourceKey(6), kind: "trial", label: "Walker 2003", pmid: "14596323"),
        SourceRef(n: SourceKey(7), kind: "trial", label: "Firoz 2001", pmid: "11794633"),
        SourceRef(n: SourceKey(8), kind: "authority", label: "EFSA", url: "https://www.efsa.europa.eu/en/efsajournal/pub/4186"),
        SourceRef(n: SourceKey(9), kind: "authority", label: "NIH ODS", url: "https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/"),
        SourceRef(n: SourceKey("P"), kind: "practice rule", label: "Our practice rule"),
    ]

    private static func evidence(_ level: EvidenceLevel, _ line: String?, _ basis: [String]) -> SupplementEvidence {
        SupplementEvidence(level: level, line: line, basis: basis.map(SourceKey.init(_:)))
    }

    static let uses: [SupplementPage.UseRef] = [
        SupplementPage.UseRef(key: "migraine", slug: "demo-magnesium-for-migraine", title: "Magnesium for migraine", pillar: "stress",
                              evidence: evidence(.moderate, nil, ["4"]), summary: "10 trials: fewer and milder attacks"),
        SupplementPage.UseRef(key: "blood-sugar", slug: "demo-magnesium-for-blood-sugar", title: "Magnesium for blood sugar", pillar: "energie",
                              evidence: evidence(.moderate, nil, ["5"]), summary: "In people with, or at risk of, diabetes"),
        SupplementPage.UseRef(key: "sleep", slug: "demo-magnesium-for-sleep", title: "Magnesium for sleep", pillar: "sommeil",
                              evidence: evidence(.limited, nil, ["1"]), summary: "3 small trials in older adults"),
        SupplementPage.UseRef(key: "stress", slug: "demo-magnesium-for-stress", title: "Magnesium for stress and anxiety", pillar: "stress",
                              evidence: evidence(.limited, nil, ["2"]), summary: "Promising, but the studies are weak"),
        SupplementPage.UseRef(key: "muscle-cramps", slug: "demo-magnesium-for-muscle-cramps", title: "Magnesium for muscle cramps", pillar: "mouvement",
                              evidence: evidence(.notSupported, nil, ["3"]), summary: "No clear benefit in older adults"),
    ]

    static let magnesium = SupplementPage(
        name: "Magnesium", slug: pageSlug, category: "Mineral",
        line: "A mineral your nerves and muscles rely on. Some of its uses are well studied; others less than their reputation suggests.",
        visual: magnesiumVisual,
        benefits: [
            item("Fewer and milder migraine attacks", ["4"], use: "migraine"),
            item("Better fasting blood sugar, if yours runs high", ["5"], use: "blood-sugar"),
            item("Falling asleep a little sooner", ["1"], use: "sleep"),
        ],
        physiology: SupplementPage.Physiology(
            role: [item("Helps more than 300 enzymes work, including the ones that make energy.", ["9"])],
            stored: [item("Mostly in your bones. Less than 1% is in your blood, so a normal blood test doesn't rule out a low level.", ["9"])],
            absorbed: [item("In the gut; your kidneys keep the balance.", ["9"])],
            loweredBy: [item("Alcohol, long-term stomach-acid reducers and some diuretics, and diarrhoea.", ["9"])]
        ),
        uses: uses,
        label: [
            item("Look for the amount of magnesium itself (\"elemental\"), not the weight of the whole compound.", ["9"]),
            item("Citrate and glycinate (amino-acid chelates) and chloride are absorbed better than oxide.", ["6", "7"]),
        ],
        askFirst: [
            item("You have kidney problems.", ["9"]),
            item("You take some antibiotics, osteoporosis medicine (bisphosphonates), diuretics or stomach-acid reducers.", ["9"]),
            item("You are pregnant or breastfeeding.", ["P"]),
        ],
        sideEffects: [item("Loose stools and stomach upset are the most common.", ["3"])],
        upperLimits: [item("250 mg a day of magnesium from supplements, for adults.", ["8"])],
        food: ["Pumpkin seeds", "Almonds", "Cooked spinach", "Black beans", "Dark chocolate", "Oats"].map { SupplementPage.Food(name: $0) },
        habits: [],
        articles: ["demo-sleep-repair-2", "demo-nsdr", "demo-breathing-exercises"],
        sources: sources
    )

    static let creatine = SupplementPage(
        name: "Creatine", slug: "demo-creatine", line: "Strength, power, and support for the brain.", visual: creatineVisual
    )

    private static let parent = SupplementUse.Parent(name: "Magnesium", slug: pageSlug)

    static let useRowsDetail: [SupplementUse] = [
        SupplementUse(supplement: parent, key: "sleep", title: "Magnesium for sleep", pillar: "sommeil",
                      evidence: evidence(.limited, "In three small trials of older adults with insomnia, people fell asleep about 17 minutes sooner. Total sleep time did not clearly change, and the trials were small and of low quality.", ["1"]),
                      benefits: [item("Falling asleep a little sooner", ["1"])],
                      forms: [item("Glycinate or citrate: absorbed better than oxide.", ["6"])],
                      label: [item("Magnesium glycinate or citrate, with the elemental amount per capsule stated.")],
                      askFirst: [item("Kidney problems, some medicines, pregnancy or breastfeeding.", ["9"])],
                      articles: ["demo-sleep-repair-2"],
                      sources: cited(["1", "6", "9"])),
        SupplementUse(supplement: parent, key: "migraine", title: "Magnesium for migraine", pillar: "stress",
                      evidence: evidence(.moderate, "10 trials: fewer and milder attacks", ["4"]),
                      benefits: [item("Fewer and milder migraine attacks", ["4"])],
                      askFirst: [item("Kidney problems, some medicines, pregnancy or breastfeeding.", ["9"])],
                      sources: cited(["4", "9"])),
        SupplementUse(supplement: parent, key: "blood-sugar", title: "Magnesium for blood sugar", pillar: "energie",
                      evidence: evidence(.moderate, "In people with, or at risk of, diabetes", ["5"]),
                      benefits: [item("Better fasting blood sugar, if yours runs high", ["5"])],
                      askFirst: [item("Kidney problems, some medicines, pregnancy or breastfeeding.", ["9"])],
                      sources: cited(["5", "9"])),
        SupplementUse(supplement: parent, key: "stress", title: "Magnesium for stress and anxiety", pillar: "stress",
                      evidence: evidence(.limited, "Promising, but the studies are weak", ["2"]),
                      askFirst: [item("Kidney problems, some medicines, pregnancy or breastfeeding.", ["9"])],
                      articles: ["demo-breathing-exercises"],
                      sources: cited(["2", "9"])),
        SupplementUse(supplement: parent, key: "muscle-cramps", title: "Magnesium for muscle cramps", pillar: "mouvement",
                      evidence: evidence(.notSupported, "In older adults with night-time leg cramps, magnesium worked no better than a placebo. For cramps in pregnancy the studies disagree, and no trial has tested cramps from exercise.", ["3"]),
                      sources: cited(["3"])),
    ]

    private static func cited(_ keys: [String]) -> [SourceRef] {
        SupplementLogic.cited(keys.map(SourceKey.init(_:)), in: sources)
    }

    /// The use rows as the catalog lists them (tagged `supplement-use` + `supplement-of:demo-magnesium`).
    static let useRows: [LibResource] = uses.map { u in
        LibResource(slug: u.slug, title: u.title, summary: u.summary ?? "", pillar: u.pillar ?? "nutrition", supplement: true, locked: false,
                    publishedAt: nil, coverURL: nil, supplementUse: true, supplementOf: pageSlug)
    }

    static func content(slug: String) -> SupplementEntry.Content? {
        if slug == pageSlug { return .page(magnesium) }
        if slug == creatine.slug { return .page(creatine) }
        if let use = useRowsDetail.first(where: { "\(pageSlug)-for-\($0.key)" == slug }) { return .use(use) }
        return nil
    }
}
