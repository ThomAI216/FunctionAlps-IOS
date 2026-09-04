// Direct wearable connectors — the vendor-independent core (owner decision 2026-09-04: free, direct
// OAuth integrations only; no aggregator). One adapter per vendor implements `VendorAdapter`; the five
// functions (`wearable-oauth-start`, `wearable-oauth-callback`, `wearable-vendor-webhook`,
// `wearable-vendor-sync`, `wearable-vendor-disconnect`) are vendor-agnostic and route through the
// registry. Tokens never sit in clear text: AES-256-GCM with the `WEARABLE_TOKEN_KEY` secret
// (32 random bytes, base64) — rotate by re-encrypting; a lost key means "reconnect", never a leak.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

export type VendorKey = "oura" | "whoop" | "polar" | "garmin" | "withings" | "suunto" | "google"

/** Stable `data_source_id` per direct vendor: 1000000 + a number that never collides with Apple Health (1000001). */
export const VENDOR_SOURCE_IDS: Record<VendorKey, number> = {
  oura: 1000018,
  whoop: 1000042,
  polar: 1000003,
  garmin: 1000002,
  withings: 1000008,
  suunto: 1000050,
  google: 1000011,
}

export interface TokenSet {
  accessToken: string
  refreshToken?: string
  /** Unix seconds when the access token expires; undefined = non-expiring (Polar). */
  expiresAt?: number
  scopes?: string[]
  /** The vendor's id for this user (Oura/WHOOP user id, Polar member-id, Withings userid, Garmin userId…). */
  vendorUserId?: string
  raw?: Record<string, unknown>
}

export interface DailyRow {
  day: string                  // YYYY-MM-DD in the member's day (vendor-local)
  dataTypeId: number
  dataTypeName: string
  value: number | null
  valueText?: string | null
  valueType?: "LONG" | "DOUBLE" | "STRING" | "DATE" | "BOOLEAN"
  timezoneOffset?: number | null
  details?: Record<string, unknown> | null
  recordedAt?: string | null
}

export interface EpochRow {
  startTs: string
  endTs?: string | null
  dataTypeId: number
  dataTypeName: string
  value: number | null
  valueText?: string | null
  valueType?: "LONG" | "DOUBLE" | "STRING" | "DATE" | "BOOLEAN"
  timezoneOffset?: number | null
  details?: Record<string, unknown> | null
}

export interface WebhookEvent {
  /** The vendor's user id the event is about (resolved to a patient through wearable_vendor_accounts). */
  vendorUserId: string
  /** What changed, free text per vendor (sleep / activity / workout / measure …). */
  kind: string
  /** Inclusive day range to (re)pull; undefined = the last 3 days. */
  windowStart?: string
  windowEnd?: string
  /** Some vendors push the data itself; the adapter can hand rows back directly. */
  rows?: { daily: DailyRow[]; epoch: EpochRow[] }
  /** Deauthorisation from the vendor side: mark the account revoked, pull nothing. */
  revoked?: boolean
}

export interface AccountContext {
  patientId: string
  vendorUserId: string | null
  meta: Record<string, unknown>
}

export interface VendorAdapter {
  key: VendorKey
  name: string
  /** OAuth 2.0 code flow. */
  usesPKCE: boolean
  scopes: string[]
  authorizeURL(p: { clientId: string; redirectUri: string; state: string; codeChallenge?: string }): string
  exchangeCode(p: { code: string; redirectUri: string; codeVerifier?: string }): Promise<TokenSet>
  refresh(refreshToken: string): Promise<TokenSet>
  /** Best-effort token revocation at the vendor (undefined = the vendor has no endpoint). */
  revoke?(tokens: TokenSet): Promise<void>
  /** After the first exchange: register the user / subscribe to notifications where the vendor needs it. */
  afterConnect?(tokens: TokenSet, ctx: { patientId: string; webhookUrl: string }): Promise<Partial<TokenSet> & { meta?: Record<string, unknown> }>
  /** Verify + parse an inbound webhook. Return [] for a valid ping that carries nothing. Throw on a bad signature. */
  parseWebhook(req: Request, rawBody: string, url: URL): Promise<WebhookEvent[] | "challenge"> | WebhookEvent[] | "challenge"
  /** Answer a verification handshake (some vendors GET a challenge). */
  challengeResponse?(url: URL, rawBody: string): Response | null
  /** Pull the days [start, end] (inclusive, YYYY-MM-DD) and map them to catalogue rows. */
  fetchRange(tokens: TokenSet, start: string, end: string, ctx: AccountContext): Promise<{ daily: DailyRow[]; epoch: EpochRow[] }>
}

// MARK: - Catalogue ids (wearable_data_types) the adapters write

export const T = {
  Steps: 1000, CoveredDistance: 1001, BurnedCalories: 1010, ActiveBurnedCalories: 1011, ActivityDuration: 1100,
  SleepEfficiency: 2200,
  MainSleepDuration: 2300, InBed: 2301, REM: 2302, Deep: 2303, Light: 2305, Awake: 2306, Latency: 2307, Interruptions: 2402,
  HeartRate: 3000, HeartRateResting: 3001, SPO2: 3009, VO2max: 3030, Rmssd: 3100, RmssdSleep: 3106, SDNN: 3112,
  RespirationRate: 4000, Weight: 5020, AverageStress: 6010,
  // Reserved ≥ 1000100 (migration 20260904_wearable_direct_connectors): vendor scores + the catalogue gaps.
  ReadinessScore: 1000100, RecoveryScore: 1000101, StrainScore: 1000102, BodyBattery: 1000103, ANSCharge: 1000104,
  SleepScore: 1000105, SkinTemperatureDeviation: 1000106, BloodGlucose: 1000107, MenstrualCycleDay: 1000108,
  StressScore: 1000109, SkinTemperature: 1000110, BodyFatPercent: 1000111, DiastolicBP: 1000112, SystolicBP: 1000113,
} as const

export const NAMES: Record<number, string> = {
  1000: "Steps", 1001: "CoveredDistance", 1010: "BurnedCalories", 1011: "ActiveBurnedCalories", 1100: "ActivityDuration",
  2200: "SleepEfficiency", 2300: "ThryveMainSleepDuration", 2301: "ThryveMainSleepInBedDuration", 2302: "ThryveMainSleepREMDuration",
  2303: "ThryveMainSleepDeepDuration", 2305: "ThryveMainSleepLightDuration", 2306: "ThryveMainSleepAwakeDuration", 2307: "ThryveMainSleepLatency",
  2402: "ThryveMainSleepInterruptions", 3000: "HeartRate", 3001: "HeartRateResting", 3009: "SPO2", 3030: "VO2max", 3100: "Rmssd",
  3106: "RmssdSleep", 3112: "SDNN", 4000: "RespirationRate", 5020: "Weight", 6010: "AverageStress",
  1000100: "ReadinessScore", 1000101: "RecoveryScore", 1000102: "StrainScore", 1000103: "BodyBattery", 1000104: "ANSCharge",
  1000105: "SleepScore", 1000106: "SkinTemperatureDeviation", 1000107: "BloodGlucose", 1000108: "MenstrualCycleDay",
  1000109: "StressScore", 1000110: "SkinTemperature", 1000111: "BodyFatPercent", 1000112: "DiastolicBP", 1000113: "SystolicBP",
}

/** A daily row with the catalogue name filled in; nulls and NaN are dropped by the caller. */
export function daily(day: string, id: number, value: number | null | undefined, extra: Partial<DailyRow> = {}): DailyRow | null {
  if (value == null || !Number.isFinite(value)) return null
  return { day, dataTypeId: id, dataTypeName: NAMES[id] ?? String(id), value, valueType: Number.isInteger(value) ? "LONG" : "DOUBLE", ...extra }
}

export function epoch(startTs: string, id: number, value: number | null | undefined, extra: Partial<EpochRow> = {}): EpochRow | null {
  if (value == null || !Number.isFinite(value)) return null
  return { startTs, dataTypeId: id, dataTypeName: NAMES[id] ?? String(id), value, valueType: Number.isInteger(value) ? "LONG" : "DOUBLE", ...extra }
}

export const compact = <R>(rows: (R | null)[]): R[] => rows.filter((r): r is R => r != null)

/** YYYY-MM-DD for a Date in a given UTC offset (minutes). */
export function localDay(d: Date, offsetMinutes = 0): string {
  return new Date(d.getTime() + offsetMinutes * 60_000).toISOString().slice(0, 10)
}

export function addDays(day: string, n: number): string {
  const d = new Date(day + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10)
}

export function daysBetween(start: string, end: string): string[] {
  const out: string[] = []; let d = start
  while (d <= end && out.length < 400) { out.push(d); d = addDays(d, 1) }
  return out
}

// MARK: - Secrets, crypto, PKCE, state

export function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name) ?? fallback
  if (v == null) throw new Error(`missing secret ${name}`)
  return v
}

export function vendorClient(vendor: VendorKey): { clientId: string; clientSecret: string } {
  const up = vendor.toUpperCase()
  return { clientId: env(`${up}_CLIENT_ID`), clientSecret: env(`${up}_CLIENT_SECRET`, "") }
}

async function aesKey(): Promise<CryptoKey> {
  const raw = Uint8Array.from(atob(env("WEARABLE_TOKEN_KEY")), (c) => c.charCodeAt(0))
  if (raw.length !== 32) throw new Error("WEARABLE_TOKEN_KEY must be 32 bytes base64")
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"])
}

export async function encrypt(text: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(), new TextEncoder().encode(text)))
  const out = new Uint8Array(iv.length + ct.length); out.set(iv); out.set(ct, iv.length)
  return "v1." + btoa(String.fromCharCode(...out))
}

export async function decrypt(blob: string): Promise<string> {
  if (!blob.startsWith("v1.")) throw new Error("unknown token blob version")
  const bytes = Uint8Array.from(atob(blob.slice(3)), (c) => c.charCodeAt(0))
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, await aesKey(), bytes.slice(12))
  return new TextDecoder().decode(pt)
}

export function randomToken(bytes = 32): string {
  const b = crypto.getRandomValues(new Uint8Array(bytes))
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export async function pkceChallenge(verifier: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)))
  return btoa(String.fromCharCode(...digest)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export async function hmacSha256(secret: string, data: string, encoding: "hex" | "base64" = "hex"): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data)))
  if (encoding === "base64") return btoa(String.fromCharCode(...sig))
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("")
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let r = 0
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return r === 0
}

/** OAuth token endpoint POST with either Basic client auth or client credentials in the body. */
export async function tokenPost(url: string, params: Record<string, string>, auth: { basic?: { id: string; secret: string }; headers?: Record<string, string> } = {}): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json", ...(auth.headers ?? {}) }
  if (auth.basic) headers.Authorization = "Basic " + btoa(`${auth.basic.id}:${auth.basic.secret}`)
  const resp = await fetch(url, { method: "POST", headers, body: new URLSearchParams(params) })
  const text = await resp.text()
  if (!resp.ok) throw new Error(`token endpoint ${resp.status}: ${text.slice(0, 300)}`)
  return JSON.parse(text)
}

export async function getJSON(url: string, headers: Record<string, string>): Promise<Record<string, unknown>> {
  const resp = await fetch(url, { headers: { Accept: "application/json", ...headers } })
  const text = await resp.text()
  if (resp.status === 401) throw new UnauthorizedError(text.slice(0, 200))
  if (resp.status === 429) throw new RateLimitedError(resp.headers.get("Retry-After"))
  if (!resp.ok) throw new Error(`GET ${url.split("?")[0]} ${resp.status}: ${text.slice(0, 300)}`)
  return text ? JSON.parse(text) : {}
}

export class UnauthorizedError extends Error { constructor(m: string) { super("unauthorized: " + m); this.name = "UnauthorizedError" } }
export class RateLimitedError extends Error { retryAfter: number; constructor(h: string | null) { super("rate limited"); this.name = "RateLimitedError"; this.retryAfter = Number(h ?? 60) || 60 } }

// MARK: - Supabase

export function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } })
}

/** The caller's patient id from the bearer JWT (member functions). */
export async function resolvePatientId(req: Request, db: SupabaseClient): Promise<string | null> {
  const auth = req.headers.get("Authorization")
  if (!auth?.startsWith("Bearer ")) return null
  const { data: { user }, error } = await db.auth.getUser(auth.slice(7))
  if (error || !user) return null
  const { data } = await db.from("patients").select("id").eq("auth_user_id", user.id).maybeSingle()
  return data?.id ?? null
}

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
}
export const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

export function functionsBase(): string {
  return env("WEARABLE_FUNCTIONS_BASE", `${env("SUPABASE_URL")}/functions/v1`)
}

/** Where the vendor sends the member back after consent — our callback function. */
export function oauthRedirectUri(): string { return `${functionsBase()}/wearable-oauth-callback` }
export function webhookUrl(vendor: VendorKey): string { return `${functionsBase()}/wearable-vendor-webhook/${vendor}` }
/** Where the callback sends the phone: the app's URL scheme. */
export const APP_RETURN_URL = "functionalps://wearables/callback"

// MARK: - Accounts (wearable_vendor_accounts)

export interface AccountRow {
  id: string
  patient_id: string
  vendor: VendorKey
  vendor_user_id: string | null
  access_token_enc: string | null
  refresh_token_enc: string | null
  token_expires_at: string | null
  scopes: string[] | null
  status: "connected" | "revoked" | "error"
  meta: Record<string, unknown> | null
}

export async function storeTokens(db: SupabaseClient, patientId: string, vendor: VendorKey, tokens: TokenSet, meta?: Record<string, unknown>) {
  const row = {
    patient_id: patientId, vendor,
    vendor_user_id: tokens.vendorUserId ?? null,
    access_token_enc: await encrypt(tokens.accessToken),
    refresh_token_enc: tokens.refreshToken ? await encrypt(tokens.refreshToken) : null,
    token_expires_at: tokens.expiresAt ? new Date(tokens.expiresAt * 1000).toISOString() : null,
    scopes: tokens.scopes ?? null,
    status: "connected", last_error: null, revoked_at: null,
    meta: meta ?? null,
    updated_at: new Date().toISOString(),
  }
  const { error } = await db.from("wearable_vendor_accounts").upsert(row, { onConflict: "patient_id,vendor" })
  if (error) throw new Error(`account upsert: ${error.message}`)
}

/** Decrypted tokens for an account, refreshed when within 2 minutes of expiry (persisting the new set). */
export async function liveTokens(db: SupabaseClient, account: AccountRow, adapter: VendorAdapter): Promise<TokenSet> {
  if (!account.access_token_enc) throw new UnauthorizedError("no token")
  let tokens: TokenSet = {
    accessToken: await decrypt(account.access_token_enc),
    refreshToken: account.refresh_token_enc ? await decrypt(account.refresh_token_enc) : undefined,
    expiresAt: account.token_expires_at ? Math.floor(new Date(account.token_expires_at).getTime() / 1000) : undefined,
    vendorUserId: account.vendor_user_id ?? undefined,
    scopes: account.scopes ?? undefined,
  }
  const soon = Math.floor(Date.now() / 1000) + 120
  if (tokens.expiresAt && tokens.expiresAt < soon) {
    if (!tokens.refreshToken) throw new UnauthorizedError("expired, no refresh token")
    const fresh = await adapter.refresh(tokens.refreshToken)
    tokens = { ...tokens, ...fresh, refreshToken: fresh.refreshToken ?? tokens.refreshToken, vendorUserId: fresh.vendorUserId ?? tokens.vendorUserId }
    await storeTokens(db, account.patient_id, account.vendor, tokens, account.meta ?? undefined)
  }
  return tokens
}

export async function markAccount(db: SupabaseClient, id: string, patch: Record<string, unknown>) {
  await db.from("wearable_vendor_accounts").update({ ...patch, updated_at: new Date().toISOString() }).eq("id", id)
}

/** Mirror into `wearable_connections` (what the app and the dashboard read). */
export async function upsertConnection(db: SupabaseClient, patientId: string, vendor: VendorKey, connected: boolean) {
  const now = new Date().toISOString()
  const row: Record<string, unknown> = { patient_id: patientId, data_source_id: VENDOR_SOURCE_IDS[vendor], data_source_name: vendor, status: connected ? "connected" : "disconnected", updated_at: now }
  if (connected) row.connected_at = now; else row.disconnected_at = now
  const { error } = await db.from("wearable_connections").upsert(row, { onConflict: "patient_id,data_source_id" })
  if (error) throw new Error(`connection upsert: ${error.message}`)
}

// MARK: - Rows → tables

export async function persistRows(db: SupabaseClient, patientId: string, vendor: VendorKey, rows: { daily: DailyRow[]; epoch: EpochRow[] }, rawEventId: string | null) {
  const sourceId = VENDOR_SOURCE_IDS[vendor]
  const dailyRows = rows.daily.map((d) => ({
    patient_id: patientId, data_source_id: sourceId, day: d.day, data_type_id: d.dataTypeId, data_type_name: d.dataTypeName,
    value: d.value, value_text: d.valueText ?? null, value_type: d.valueType ?? null, timezone_offset: d.timezoneOffset ?? null,
    details: d.details ?? null, raw_event_id: rawEventId, recorded_at: d.recordedAt ?? null,
  }))
  const epochRows = rows.epoch.map((e) => ({
    patient_id: patientId, data_source_id: sourceId, data_type_id: e.dataTypeId, data_type_name: e.dataTypeName,
    value: e.value, value_text: e.valueText ?? null, value_type: e.valueType ?? null, start_ts: e.startTs, end_ts: e.endTs ?? null,
    timezone_offset: e.timezoneOffset ?? null, details: e.details ?? null, raw_event_id: rawEventId,
  }))
  // Dedupe inside the batch on the natural keys (PostgREST refuses duplicate conflict targets in one upsert).
  const seenD = new Set<string>(); const uniqD = dailyRows.filter((r) => { const k = `${r.day}|${r.data_type_id}`; if (seenD.has(k)) return false; seenD.add(k); return true })
  const seenE = new Set<string>(); const uniqE = epochRows.filter((r) => { const k = `${r.data_type_id}|${r.start_ts}`; if (seenE.has(k)) return false; seenE.add(k); return true })
  for (let i = 0; i < uniqD.length; i += 500) {
    const { error } = await db.from("wearable_daily").upsert(uniqD.slice(i, i + 500), { onConflict: "patient_id,data_source_id,day,data_type_id" })
    if (error) throw new Error(`daily upsert: ${error.message}`)
  }
  for (let i = 0; i < uniqE.length; i += 500) {
    const { error } = await db.from("wearable_epoch").upsert(uniqE.slice(i, i + 500), { onConflict: "patient_id,data_source_id,data_type_id,start_ts" })
    if (error) throw new Error(`epoch upsert: ${error.message}`)
  }
  return { daily: uniqD.length, epoch: uniqE.length }
}

export async function storeRaw(db: SupabaseClient, patientId: string | null, vendor: VendorKey, kind: "oauth_callback" | "vendor_webhook" | "vendor_api", payload: unknown, vendorUserId?: string | null): Promise<string | null> {
  const { data, error } = await db.from("wearable_raw_events").insert({ patient_id: patientId, provider: vendor, end_user_id: vendorUserId ?? null, kind, payload }).select("id").single()
  if (error) { console.error("[wearables] raw insert", error.message); return null }
  return data?.id ?? null
}

export async function enqueue(db: SupabaseClient, patientId: string | null, vendor: VendorKey, vendorUserId: string, kind: string, windowStart?: string, windowEnd?: string, rawEventId?: string | null) {
  const { error } = await db.from("wearable_sync_queue").insert({
    patient_id: patientId, end_user_id: vendorUserId, notification_type: kind, data_source_id: VENDOR_SOURCE_IDS[vendor], vendor,
    granularity: "daily", window_start: windowStart ? `${windowStart}T00:00:00Z` : null, window_end: windowEnd ? `${windowEnd}T23:59:59Z` : null,
    raw_event_id: rawEventId ?? null,
  })
  if (error) console.error("[wearables] enqueue", error.message)
}
