// Structured JSON logs for the wearable functions (strategy 2026-09-14, Phase 1 item 8).
// One line per event, machine-readable, and REDACTED BY CONSTRUCTION: any field whose name looks
// like a secret, a token, an OAuth code, a raw body or a health value is dropped before it is
// written. Patient ids are hashed (first 12 hex of SHA-256) so a log line can be correlated but
// never joined back to a person without the database.

export type Level = "debug" | "info" | "warn" | "error"

const REDACT = /token|secret|code|password|authorization|cookie|body|payload|value|verifier|signature|email|phone|name$/i

let salt: string | null = null
async function saltValue(): Promise<string> {
  if (salt == null) salt = Deno.env.get("WEARABLE_LOG_SALT") ?? Deno.env.get("SUPABASE_URL") ?? "functionalps"
  return salt
}

/** Stable short hash for ids that must not appear in clear text. */
export async function hashId(id: string | null | undefined): Promise<string | null> {
  if (!id) return null
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${await saltValue()}|${id}`)))
  return Array.from(digest.slice(0, 6)).map((b) => b.toString(16).padStart(2, "0")).join("")
}

function scrub(fields: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(fields)) {
    if (REDACT.test(k)) continue
    if (v == null) { out[k] = v; continue }
    if (typeof v === "object" && !Array.isArray(v)) { out[k] = scrub(v as Record<string, unknown>); continue }
    if (typeof v === "string" && v.length > 300) { out[k] = v.slice(0, 300) + "…"; continue }
    out[k] = v
  }
  return out
}

export interface LogFields {
  fn: string
  vendor?: string | null
  account?: string | null
  job?: string | null
  patientHash?: string | null
  code?: never
  [k: string]: unknown
}

/** Emits one JSON line. Fields named like secrets are dropped, whatever they contain. */
export function log(level: Level, event: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ ts: new Date().toISOString(), level, event, ...scrub(fields) })
  if (level === "error") console.error(line)
  else if (level === "warn") console.warn(line)
  else console.log(line)
}

/** A timer for durations in log lines: `const t = timer(); … log("info", "x", { ms: t() })`. */
export function timer(): () => number {
  const t0 = performance.now()
  return () => Math.round(performance.now() - t0)
}

/** The visible part of an error for a log line: class + the first 200 chars, never a body. */
export function errorSummary(e: unknown): { errorClass: string; message: string; status?: number } {
  const err = e as { name?: string; message?: string; status?: number }
  return { errorClass: err?.name ?? "Error", message: String(err?.message ?? e).slice(0, 200), ...(err?.status ? { status: err.status } : {}) }
}

export const _logTest = { scrub }
