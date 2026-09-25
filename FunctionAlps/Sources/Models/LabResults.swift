import Foundation

// The member's released lab results — the wire row, the domain shape, and the pure rules between
// them. Foundation only, so the whole file runs under Swift Testing without a simulator.
//
// Source of truth: the CM OS function `public.get_member_lab_results()` (CLINICAL migration
// 223_labs_member_read_hardening.sql, SECURITY DEFINER). It returns one row per marker line of
// the calling member's APPROVED releases, read from the frozen release content. Drafts and revoked
// releases return nothing, and members have no SELECT on any lab table — the approval edge is in
// the database, never in this app.
//
// MIRRORED LOGIC — re-sync trigger: `LabResultsLogic.group` is copy 3 of `groupMemberRows`
// (CLINICAL `lib/labs/member-results.ts`, copy 1) and `groupResults` (Expo `patient-app/lib/labs/
// results.ts`, copy 2). Three copies is the extraction signal the programme named; until the shared
// contract package exists, a change to the function's columns or to that grouping is followed here
// by hand, and `LabResultsLogicTests` is re-fixtured from the SOURCE (the migration), not from a copy.

/// One row of `get_member_lab_results()`. Field names are the function's columns in camelCase
/// (`JSON.decoder` converts); the `columns` list is what the request pins with `select=`.
struct LabResultRow: Decodable, Sendable, Equatable {
    struct PhaseUpdate: Decodable, Sendable, Equatable {
        let title: String?
        let summaryMd: String?
    }

    struct NextStep: Decodable, Sendable, Equatable {
        let kind: String?
        let statementMd: String?
    }

    let releaseId: String
    let labRunId: String
    let sampledAt: Date?
    let language: String?
    let headlineMd: String?
    let whatWeSawMd: String?
    let whatItMeansMd: String?
    let whatWeDoNextMd: String?
    /// `{title, summary_md}` — the care-plan phase key is stripped server-side; it is internal.
    let phaseUpdate: PhaseUpdate?
    let nextSteps: [NextStep]?
    let biomarkerResultId: String
    let label: String?
    let value: String?
    let unit: String?
    let status: String?
    let whyItMattersMd: String?
    let inYourPlanMd: String?
    let patientSafeExplanation: String?
    let sortOrder: Int

    /// Exactly the columns the loader asks for — the whole member contract, nothing clinician-only.
    static let columns = [
        "release_id", "lab_run_id", "sampled_at", "language",
        "headline_md", "what_we_saw_md", "what_it_means_md", "what_we_do_next_md",
        "phase_update", "next_steps",
        "biomarker_result_id", "label", "value", "unit", "status",
        "why_it_matters_md", "in_your_plan_md", "patient_safe_explanation", "sort_order",
    ]
}

/// The three member states. A line with any other status is dropped, never guessed at.
enum LabMarkerStatus: String, Sendable, Hashable, CaseIterable {
    case inRange = "in_range"
    case watch
    case outOfRange = "out_of_range"
}

/// The language the release was written in. The frame around it follows the release, not the phone.
enum LabResultLanguage: String, Sendable, Hashable, CaseIterable {
    case fr, en, it, de
}

struct LabMarker: Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    /// As the lab printed it. Never parsed into a number here (a derived number with a missing input lies).
    let value: String
    let unit: String?
    let status: LabMarkerStatus
    let whyItMatters: String
    let inYourPlan: String?
    let explanation: String?
}

struct LabResult: Sendable, Hashable, Identifiable {
    struct PhaseUpdate: Sendable, Hashable {
        let title: String
        let summary: String
    }

    struct NextStep: Sendable, Hashable {
        let kind: String
        let statement: String
    }

    var id: String { releaseId }
    let releaseId: String
    let labRunId: String
    let sampledAt: Date?
    let language: LabResultLanguage
    let headline: String
    let whatWeSaw: String
    let whatItMeans: String
    let whatWeDoNext: String
    let phaseUpdate: PhaseUpdate?
    let nextSteps: [NextStep]
    let markers: [LabMarker]
}

/// One earlier reading of the same marker (the marker sheet's history list).
struct LabEarlierValue: Sendable, Hashable {
    let sampledAt: Date?
    let value: String
    let unit: String?
    let status: LabMarkerStatus
}

enum LabResultsLogic {
    /// Rows → results, newest first; lines in the order the release lists them.
    static func group(_ rows: [LabResultRow]) -> [LabResult] {
        // Ordered by sort_order, ties by arrival — deterministic whatever the sort's stability.
        let ordered = rows.enumerated().sorted { a, b in
            a.element.sortOrder != b.element.sortOrder ? a.element.sortOrder < b.element.sortOrder : a.offset < b.offset
        }.map(\.element)

        var order: [String] = []
        var heads: [String: LabResult] = [:]
        var lines: [String: [LabMarker]] = [:]

        for row in ordered {
            guard let raw = row.status, let status = LabMarkerStatus(rawValue: raw) else { continue }
            if heads[row.releaseId] == nil {
                order.append(row.releaseId)
                heads[row.releaseId] = head(row)
            }
            lines[row.releaseId, default: []].append(LabMarker(
                id: row.biomarkerResultId,
                label: row.label ?? "",
                value: row.value ?? "",
                unit: row.unit,
                status: status,
                whyItMatters: row.whyItMattersMd ?? "",
                inYourPlan: row.inYourPlanMd,
                explanation: row.patientSafeExplanation
            ))
        }

        let results = order.compactMap { id -> LabResult? in
            guard let h = heads[id] else { return nil }
            return LabResult(
                releaseId: h.releaseId, labRunId: h.labRunId, sampledAt: h.sampledAt, language: h.language,
                headline: h.headline, whatWeSaw: h.whatWeSaw, whatItMeans: h.whatItMeans, whatWeDoNext: h.whatWeDoNext,
                phaseUpdate: h.phaseUpdate, nextSteps: h.nextSteps, markers: lines[id] ?? []
            )
        }
        // Newest first; an undated release sorts last; equal dates keep their arrival order.
        return results.enumerated().sorted { a, b in
            let da = a.element.sampledAt ?? .distantPast, db = b.element.sampledAt ?? .distantPast
            return da != db ? da > db : a.offset < b.offset
        }.map(\.element)
    }

    private static func head(_ row: LabResultRow) -> LabResult {
        let title = row.phaseUpdate?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = row.phaseUpdate?.summaryMd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let steps = (row.nextSteps ?? []).compactMap { step -> LabResult.NextStep? in
            guard let kind = step.kind, let statement = step.statementMd,
                  !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LabResult.NextStep(kind: kind, statement: statement)
        }
        return LabResult(
            releaseId: row.releaseId,
            labRunId: row.labRunId,
            sampledAt: row.sampledAt,
            language: row.language.flatMap(LabResultLanguage.init(rawValue:)) ?? .fr,
            headline: row.headlineMd ?? "",
            whatWeSaw: row.whatWeSawMd ?? "",
            whatItMeans: row.whatItMeansMd ?? "",
            whatWeDoNext: row.whatWeDoNextMd ?? "",
            phaseUpdate: !title.isEmpty && !summary.isEmpty ? LabResult.PhaseUpdate(title: title, summary: summary) : nil,
            nextSteps: steps,
            markers: []
        )
    }

    /// Flagged lines first (the ones the member came to read), then the calm ones. Order kept within each.
    static func split(_ markers: [LabMarker]) -> (flagged: [LabMarker], inRange: [LabMarker]) {
        (markers.filter { $0.status != .inRange }, markers.filter { $0.status == .inRange })
    }

    static func counts(_ markers: [LabMarker]) -> [LabMarkerStatus: Int] {
        var out: [LabMarkerStatus: Int] = [.inRange: 0, .watch: 0, .outOfRange: 0]
        for m in markers { out[m.status, default: 0] += 1 }
        return out
    }

    /// The same marker in EARLIER released results, oldest first — matched by its label (the only
    /// identity a released line carries across runs). Values are shown as the lab printed them; no
    /// difference, percentage or trend is computed.
    static func earlierValues(in results: [LabResult], releaseId: String, label: String) -> [LabEarlierValue] {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let current = results.first(where: { $0.releaseId == releaseId }), !key.isEmpty else { return [] }
        let now = current.sampledAt ?? .distantPast
        return results
            .filter { $0.releaseId != releaseId && ($0.sampledAt ?? .distantPast) < now }
            .flatMap { r in
                r.markers
                    .filter { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
                    .map { LabEarlierValue(sampledAt: r.sampledAt, value: $0.value, unit: $0.unit, status: $0.status) }
            }
            .sorted { ($0.sampledAt ?? .distantPast) < ($1.sampledAt ?? .distantPast) }
    }
}

// MARK: - The words around a release, in the release's own language

/// Everything clinical (headline, blocks, labels, explanations) comes from the release itself;
/// these are only the frame, and they follow the RELEASE language — a French release keeps a French
/// frame on an English phone. Copied verbatim from the Expo `RESULT_COPY` / CLINICAL
/// `MEMBER_SECTION_LABEL` (rule 6: no clinical wording invented in Swift).
struct LabResultCopy: Sendable {
    let saw: String
    let means: String
    let next: String
    let lines: String
    let inRange: @Sendable (Int) -> String
    let steps: String
    let phase: String
    let validated: String
    let why: String
    let plan: String
    let explanation: String
    let earlier: String
    let ask: String
    let disclaimer: String
    let statusLabels: [LabMarkerStatus: String]

    func statusLabel(_ status: LabMarkerStatus) -> String { statusLabels[status] ?? status.rawValue }

    static func forLanguage(_ language: LabResultLanguage) -> LabResultCopy {
        switch language {
        case .fr: fr
        case .en: en
        case .it: it
        case .de: de
        }
    }

    static let fr = LabResultCopy(
        saw: "Ce que nous avons vu", means: "Ce que cela signifie", next: "Ce que nous faisons",
        lines: "Vos résultats", inRange: { "\($0) dans la zone" }, steps: "Prochaines étapes", phase: "Votre plan",
        validated: "Résultats validés par votre nutritionniste",
        why: "Pourquoi c’est important", plan: "Dans votre plan", explanation: "En savoir plus",
        earlier: "Vos résultats précédents", ask: "Poser une question à votre nutritionniste",
        disclaimer: "Ce résultat ne remplace pas un avis médical.",
        statusLabels: [.inRange: "Dans la zone", .watch: "À surveiller", .outOfRange: "Hors zone"]
    )

    static let en = LabResultCopy(
        saw: "What we saw", means: "What it means", next: "What we do next",
        lines: "Your results", inRange: { "\($0) in range" }, steps: "Next steps", phase: "Your plan",
        validated: "Results reviewed and approved by your nutritionist",
        why: "Why it matters", plan: "In your plan", explanation: "Learn more",
        earlier: "Your earlier results", ask: "Ask your nutritionist a question",
        disclaimer: "This result does not replace medical advice.",
        statusLabels: [.inRange: "In range", .watch: "Keep an eye on", .outOfRange: "Out of range"]
    )

    static let it = LabResultCopy(
        saw: "Cosa abbiamo visto", means: "Cosa significa", next: "Cosa facciamo",
        lines: "I tuoi risultati", inRange: { "\($0) nella norma" }, steps: "Prossimi passi", phase: "Il tuo piano",
        validated: "Risultati convalidati dal tuo professionista della nutrizione",
        why: "Perché è importante", plan: "Nel tuo piano", explanation: "Per saperne di più",
        earlier: "I tuoi risultati precedenti", ask: "Fai una domanda al tuo professionista",
        disclaimer: "Questo risultato non sostituisce un parere medico.",
        statusLabels: [.inRange: "Nella norma", .watch: "Da monitorare", .outOfRange: "Fuori norma"]
    )

    static let de = LabResultCopy(
        saw: "Was wir gesehen haben", means: "Was es bedeutet", next: "Was wir als Nächstes tun",
        lines: "Ihre Ergebnisse", inRange: { "\($0) im Bereich" }, steps: "Nächste Schritte", phase: "Ihr Plan",
        validated: "Von Ihrem Ernährungsteam geprüfte Ergebnisse",
        why: "Warum es wichtig ist", plan: "In Ihrem Plan", explanation: "Mehr erfahren",
        earlier: "Ihre früheren Ergebnisse", ask: "Ihrem Ernährungsteam eine Frage stellen",
        disclaimer: "Dieses Ergebnis ersetzt keine ärztliche Beratung.",
        statusLabels: [.inRange: "Im Bereich", .watch: "Im Blick behalten", .outOfRange: "Außerhalb des Bereichs"]
    )
}

enum LabSampleDate {
    private static let months: [LabResultLanguage: [String]] = [
        .fr: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
        .en: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
        .it: ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"],
        .de: ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"],
    ]

    /// "12 septembre 2026" / "12 September 2026" / "12. September 2026" — the calendar day of the
    /// sample in UTC, built by hand so the three copies print the same words: a lab sample is dated,
    /// not timed, and the phone's zone must not move it to the day before or after.
    static func format(_ date: Date?, language: LabResultLanguage) -> String {
        guard let date else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = parts.day, let month = parts.month, let year = parts.year,
              let name = months[language]?[month - 1] else { return "" }
        return language == .de ? "\(day). \(name) \(year)" : "\(day) \(name) \(year)"
    }
}
