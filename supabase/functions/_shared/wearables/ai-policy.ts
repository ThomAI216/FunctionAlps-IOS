// AI data boundary for wearable data (strategy 2026-09-14, D5; corpus README rule 7,
// security/ai-data-boundaries.md). DENY BY DEFAULT: no wearable reading, derived score or vendor
// metadata reaches a language model unless a rule here says so — and today no rule does. Oura is
// contractually deny (2026 API / MCP agreement); the other vendors' terms restrict AI use or leave
// it undocumented, which is the same thing for us. Scoring stays deterministic SQL/TS, never an LLM.
//
// Anything LLM-facing (meal analysis prompts, practitioner summaries, the "ask your nutritionist"
// context builder, exports) MUST call `aiPolicy()` and act on the answer. The gate is pure and
// synchronous so it can be unit-tested and called from SQL-adjacent code paths alike.

export type Transport = "apple_health" | "vendor_direct" | "manual"
export type Purpose =
  | "scoring"              // deterministic engine (member-scores, check-in scoring)
  | "member_display"       // the member sees their own reading in the app
  | "practitioner_view"    // the practice dashboard
  | "llm_prompt"           // any prompt or context window of a language model
  | "llm_training"         // fine-tuning / evaluation sets
  | "export"               // leaving CM OS (PDF, CSV, third party)
  | "research"             // aggregate / de-identified analysis

export type Verdict = "allow" | "deny" | "legal_review_required"

export interface PolicyQuery {
  /** `wearable_vendors.key`, `"apple"` for the HealthKit relay, `"manual"` for typed values. */
  vendor: string
  transport: Transport
  /** Catalogue id or name; optional — the answer never depends on it today, but callers pass it for the audit trail. */
  metric?: number | string
  purpose: Purpose
}

/** Vendors whose terms forbid feeding their data to AI systems outright. */
const AI_FORBIDDEN_VENDORS = new Set(["oura"])

/** Vendors with restrictive or undocumented AI terms: same outcome (deny), different reason. */
const AI_RESTRICTED_VENDORS = new Set(["whoop", "polar", "garmin", "withings", "suunto", "google", "dexcom", "libre", "ultrahuman"])

export function aiPolicy(q: PolicyQuery): Verdict {
  const vendor = q.vendor.toLowerCase()
  switch (q.purpose) {
    case "scoring":
    case "member_display":
    case "practitioner_view":
      // Non-AI purposes covered by the Privacy Notice (v9 relay, v10 vendor accounts).
      return "allow"
    case "llm_prompt":
    case "llm_training":
      // No vendor is on an allow list today. Apple-relayed data is the member's own HealthKit export
      // but the practice's own rule (no health values to an LLM) still applies.
      return "deny"
    case "export":
      if (AI_FORBIDDEN_VENDORS.has(vendor)) return "deny"
      if (AI_RESTRICTED_VENDORS.has(vendor)) return "legal_review_required"
      return q.transport === "vendor_direct" ? "legal_review_required" : "allow"
    case "research":
      if (AI_FORBIDDEN_VENDORS.has(vendor)) return "deny"
      return "legal_review_required"
    default:
      return "deny"
  }
}

/** Throws unless the policy allows — for call sites where a deny must be impossible to ignore. */
export function assertAiPolicy(q: PolicyQuery): void {
  const v = aiPolicy(q)
  if (v !== "allow") throw new AiPolicyError(v, q)
}

export class AiPolicyError extends Error {
  verdict: Verdict
  query: PolicyQuery
  constructor(verdict: Verdict, query: PolicyQuery) {
    super(`ai policy ${verdict}: ${query.vendor}/${query.transport}/${query.purpose}`)
    this.name = "AiPolicyError"
    this.verdict = verdict
    this.query = query
  }
}
