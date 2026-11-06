// Direct wearable connectors — the vendor-independent core, platform v2 (strategy 2026-09-14, Phase 1).
// Owner decision 2026-09-04: free, direct OAuth integrations only; no aggregator. One adapter per vendor
// implements `VendorAdapter`; the functions (`wearable-oauth-start`, `wearable-oauth-callback`,
// `wearable-vendor-webhook`, `wearable-vendor-sync`, `wearable-vendor-disconnect`, `wearable-reconcile`)
// are vendor-agnostic and route through the registry.
//
// What v2 guarantees (each point has a test in tests/):
//   • tokens: AES-256-GCM with AAD `account_id|vendor|token_type|key_version`, versioned key ring
//     (`WEARABLE_TOKEN_KEY` = v1, `WEARABLE_TOKEN_KEY_V<n>` after rotation, `WEARABLE_TOKEN_KEY_VERSION`
//     picks the writer); v1 blobs (no AAD) still decrypt so rotation is decrypt-old → encrypt-new → CAS.
//   • refresh: one worker at a time (DB lease `wearable_token_lock`) + `token_version` compare-and-swap;
//     401 → refresh once → retry once → `reconnect_required`.
//   • OAuth state: only its SHA-256 is stored; the PKCE verifier is encrypted; consume is atomic.
//   • queue: claimed with `for update skip locked` + lease; retry taxonomy with `next_attempt_at`;
//     dead-letter after MAX_ATTEMPTS; dedupe keys.
//   • webhooks: receipts + dedupe; the raw body stored once; never a vendor call inline.
//   • kill switch: `wearable_vendors.status = 'paused'` stops every outbound call, tokens untouched.
//   • logs: structured JSON, redacted by construction (log.ts). Nothing here ever prints a token.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"
import { log } from "./log.ts"

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

/** Reserved `data_source_id`s for the two phone relays (strategy 2026-09-14): Apple Health is live at 1000001
 *  (`wearable-ingest`); Android Health Connect is RESERVED only — nothing writes it until an Android client exists. */
export const RELAY_SOURCE_IDS = { apple_health: 1000001, health_connect: 1000060 } as const

/** Bumped whenever the mapping of vendor fields → catalogue rows changes shape; stored on every row. */
export const NORMALIZATION_VERSION = "2026.09.14"

/** OAuth PKCE support as the vendor documents it (replaces the old boolean). PKCE is sent for required|supported. */
export type PkceMode = "required" | "supported" | "unsupported" | "not_documented"
export const sendsPKCE = (m: PkceMode) => m === "required" || m === "supported"

export interface TokenSet {
  accessToken: string
  refreshToken?: string
  /** Unix seconds when the access token expires; undefined = non-expiring. */
  expiresAt?: number
  scopes?: string[]
  raw?: Record<string, unknown>
}

/** What the code exchange returns: the tokens plus the identity the adapter resolved (stored on the account, never in TokenSet). */
export interface ExchangeResult extends TokenSet {
  /** The vendor's id for this user (Oura/WHOOP user id, Polar member-id, Withings userid, Garmin userId…). */
  vendorUserId?: string
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
  // provenance (platform v2)
  sourceRecordId?: string | null
  sourceResourceType?: string | null
  sourceField?: string | null
  sourceDeviceId?: string | null
  sourceModifiedAt?: string | null
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
  sourceRecordId?: string | null
  sourceResourceType?: string | null
  sourceField?: string | null
  sourceDeviceId?: string | null
  sourceModifiedAt?: string | null
}

export interface RowBatch { daily: DailyRow[]; epoch: EpochRow[] }

export interface WebhookEvent {
  vendorUserId: string
  /** What changed, free text per vendor (sleep / activity / workout / measure …). */
  kind: string
  /** The vendor's own event id when it sends one (WHOOP trace_id, Oura event id…) — the first dedupe key. */
  eventId?: string | null
  /** The vendor record the event is about, when named (WHOOP sleep/workout id, Oura object_id…). */
  resourceId?: string | null
  /** A deletion tombstone: the record named above no longer exists at the vendor (WHOOP `*.deleted`). */
  deleted?: boolean
  /** Inclusive day range to (re)pull; undefined = the last 3 days. */
  windowStart?: string
  windowEnd?: string
  /** Some vendors push the data itself; the adapter can hand rows back directly. */
  rows?: RowBatch
  /** Deauthorisation from the vendor side: mark the account revoked, pull nothing. */
  revoked?: boolean
}

export interface AccountContext {
  patientId: string
  vendorUserId: string | null
  meta: Record<string, unknown>
  accountId?: string
}

export interface VendorAdapter {
  key: VendorKey
  name: string
  pkce: PkceMode
  scopes: string[]
  /** Reconcile windows (days): nightly re-pull and the weekly deeper one. Defaults 3 / 14. */
  reconcile?: { nightlyDays: number; weeklyDays: number }
  authorizeURL(p: { clientId: string; redirectUri: string; state: string; codeChallenge?: string }): string
  exchangeCode(p: { code: string; redirectUri: string; codeVerifier?: string }): Promise<ExchangeResult>
  refresh(refreshToken: string): Promise<TokenSet>
  /** Best-effort token revocation at the vendor (undefined = the vendor has no endpoint). */
  revoke?(tokens: TokenSet, ctx: AccountContext): Promise<void>
  /** Drop per-user notification subscriptions where the vendor has them (Withings, Polar…). */
  unsubscribe?(tokens: TokenSet, ctx: AccountContext): Promise<void>
  /** After the first exchange: register the user / subscribe to notifications where the vendor needs it. */
  afterConnect?(tokens: TokenSet, ctx: { patientId: string; webhookUrl: string; vendorUserId: string | null }): Promise<Partial<ExchangeResult> & { meta?: Record<string, unknown> }>
  /** Verify + parse an inbound webhook. Return [] for a valid ping that carries nothing. Throw on a bad signature. */
  parseWebhook(req: Request, rawBody: string, url: URL): Promise<WebhookEvent[] | "challenge"> | WebhookEvent[] | "challenge"
  /** Answer a verification handshake (some vendors GET a challenge). */
  challengeResponse?(url: URL, rawBody: string): Response | null
  /** Pull the days [start, end] (inclusive, YYYY-MM-DD) and map them to catalogue rows. */
  fetchRange(tokens: TokenSet, start: string, end: string, ctx: AccountContext): Promise<RowBatch>
}

// MARK: - Catalogue ids (wearable_data_types) the adapters write — mirrors migration 20260914_wearable_catalogue_v2

export const T = {
  Steps: 1000, CoveredDistance: 1001, FloorsClimbed: 1002, ElevationGain: 1003, BurnedCalories: 1010, ActiveBurnedCalories: 1011, MET: 1012, RestingMetabolicRate: 1016,
  ActivityDuration: 1100, ActivityLow: 1101, ActivityMid: 1102, ActivityHigh: 1103, ActivitySedentary: 1104, ActivityType: 1200,
  SleepREMBinary: 2002, SleepDeepBinary: 2003, SleepLightBinary: 2005, SleepAwakeBinary: 2006,
  SleepEfficiency: 2200, SleepQuality: 2201, SleepIntensity: 2210,
  MainSleepDuration: 2300, InBed: 2301, REM: 2302, Deep: 2303, Light: 2305, Awake: 2306, Latency: 2307, AwakeAfterWakeup: 2308,
  SleepStart: 2400, SleepEnd: 2401, Interruptions: 2402,
  HeartRate: 3000, HeartRateResting: 3001, HeartRateSleep: 3002, PulseWaveVelocity: 3008, SPO2: 3009, HeartRateSleepLowest: 3020, VO2max: 3030,
  HRZoneLight: 3090, HRZoneModerate: 3091, HRZoneIntense: 3092, HRZoneMaximal: 3093,
  Rmssd: 3100, RmssdSleep: 3106, RmssdSleepHighest: 3107, SDNN: 3112, SDRR: 3113, AFib: 3120, DiastolicBP: 3300, SystolicBP: 3301,
  RespirationRate: 4000, RespirationRateSleep: 4002, Breathing: 4100, Snoring: 4101,
  Weight: 5020, MuscleMass: 5021, BoneMass: 5022, FatFreeMass: 5023, FatMass: 5024, FatRatio: 5025, BMI: 5026, WaterMass: 5029, Height: 5030,
  BodyTemperature: 5040, SkinTemperature: 5041, UndefinedTemperature: 5042,
  AverageStress: 6010, HighStress: 6011, MediumStress: 6012, LowStress: 6013,
  // Reserved ≥ 1000100 (migration 20260904_wearable_direct_connectors): vendor scores + the catalogue gaps.
  ReadinessScore: 1000100, RecoveryScore: 1000101, StrainScore: 1000102, BodyBattery: 1000103, ANSCharge: 1000104,
  SleepScore: 1000105, SkinTemperatureDeviation: 1000106, BloodGlucose: 1000107, MenstrualCycleDay: 1000108, StressScore: 1000109,
  // DEPRECATED aliases (catalogue v2, D2): kept so old code compiles; `daily()`/`epoch()` rewrite them to the canonical id.
  SkinTemperatureAlt: 1000110, BodyFatPercent: 1000111, DiastolicBPAlt: 1000112, SystolicBPAlt: 1000113,
  // Glucose summaries (catalogue v2, D1) — reserved; CGM is parked, nothing writes them yet.
  GlucoseMean: 1000114, GlucoseCV: 1000115, GlucoseTimeInConfiguredRange: 1000116, GlucoseCoverage: 1000117, GlucoseRateOfChange: 1000118,
  // Vendor-only scores (catalogue v2, D1) — the new block from 1000130.
  PolarNightlyRechargeStatus: 1000130, PolarSleepCharge: 1000131, PolarAnsStatus: 1000132, WHOOPSleepPerformance: 1000133,
  SuuntoRecoveryBalance: 1000134, SuuntoStressState: 1000135, UltrahumanMetabolicScore: 1000136, UltrahumanGlucoseVariability: 1000137, GlucoseTrendRate: 1000138,
} as const

/** Deprecated id → canonical id (catalogue v2, D2). Rows are never written under a deprecated id. */
export const CANONICAL: Record<number, number> = { 1000110: 5041, 1000111: 5025, 1000112: 3300, 1000113: 3301 }
export const canonicalId = (id: number): number => CANONICAL[id] ?? id

export const NAMES: Record<number, string> = {
  1000: "Steps", 1001: "CoveredDistance", 1002: "FloorsClimbed", 1003: "ElevationGain", 1010: "BurnedCalories", 1011: "ActiveBurnedCalories", 1012: "MetabolicEquivalent", 1016: "RestingMetabolicRate",
  1100: "ActivityDuration", 1101: "ActivityLowBinary", 1102: "ActivityMidBinary", 1103: "ActivityHighBinary", 1104: "ActivitySedentaryBinary", 1200: "ActivityType",
  2002: "SleepREMBinary", 2003: "SleepDeepBinary", 2005: "SleepLightBinary", 2006: "SleepAwakeBinary",
  2200: "SleepEfficiency", 2201: "SleepQuality", 2210: "SleepIntensity",
  2300: "ThryveMainSleepDuration", 2301: "ThryveMainSleepInBedDuration", 2302: "ThryveMainSleepREMDuration", 2303: "ThryveMainSleepDeepDuration", 2305: "ThryveMainSleepLightDuration",
  2306: "ThryveMainSleepAwakeDuration", 2307: "ThryveMainSleepLatency", 2308: "ThryveMainSleepAwakeAfterWakeup", 2400: "ThryveMainSleepStartTime", 2401: "ThryveMainSleepEndTime", 2402: "ThryveMainSleepInterruptions",
  3000: "HeartRate", 3001: "HeartRateResting", 3002: "HeartRateSleep", 3008: "PulseWaveVelocity", 3009: "SPO2", 3020: "HeartRateSleepLowest", 3030: "VO2max",
  3090: "HeartRateZoneLightDuration", 3091: "HeartRateZoneModerateDuration", 3092: "HeartRateZoneIntenseDuration", 3093: "HeartRateZoneMaximalDuration",
  3100: "Rmssd", 3106: "RmssdSleep", 3107: "RmssdSleepHighest", 3112: "SDNN", 3113: "SDRR", 3120: "AtrialFibrillationDetection", 3300: "BloodPressureDiastolic", 3301: "BloodPressureSystolic",
  4000: "RespirationRate", 4002: "RespirationRateSleep", 4100: "Breathing", 4101: "SnoringBinary",
  5020: "Weight", 5021: "MuscleMass", 5022: "BoneMass", 5023: "FatFreeMass", 5024: "FatMass", 5025: "FatRatio", 5026: "BMI", 5029: "WaterMass", 5030: "Height",
  5040: "BodyTemperature", 5041: "SkinTemperature", 5042: "UndefinedTemperature", 6010: "AverageStress", 6011: "HighStressBinary", 6012: "MediumStressBinary", 6013: "LowStressBinary",
  1000100: "ReadinessScore", 1000101: "RecoveryScore", 1000102: "StrainScore", 1000103: "BodyBattery", 1000104: "ANSCharge",
  1000105: "SleepScore", 1000106: "SkinTemperatureDeviation", 1000107: "BloodGlucose", 1000108: "MenstrualCycleDay", 1000109: "StressScore",
  1000110: "SkinTemperatureAlt", 1000111: "BodyFatPercent", 1000112: "DiastolicBPAlt", 1000113: "SystolicBPAlt",
  1000114: "GlucoseMean", 1000115: "GlucoseCV", 1000116: "GlucoseTimeInConfiguredRange", 1000117: "GlucoseCoverage", 1000118: "GlucoseRateOfChange",
  1000130: "PolarNightlyRechargeStatus", 1000131: "PolarSleepCharge", 1000132: "PolarAnsStatus", 1000133: "WHOOPSleepPerformance",
  1000134: "SuuntoRecoveryBalance", 1000135: "SuuntoStressState", 1000136: "UltrahumanMetabolicScore", 1000137: "UltrahumanGlucoseVariability", 1000138: "GlucoseTrendRate",
}

/** A daily row with the catalogue name filled in; nulls and NaN are dropped by the caller. Deprecated ids are rewritten. */
export function daily(day: string, id: number, value: number | null | undefined, extra: Partial<DailyRow> = {}): DailyRow | null {
  if (value == null || !Number.isFinite(value)) return null
  const cid = canonicalId(id)
  return { day, dataTypeId: cid, dataTypeName: NAMES[cid] ?? String(cid), value, valueType: Number.isInteger(value) ? "LONG" : "DOUBLE", ...extra }
}

export function epoch(startTs: string, id: number, value: number | null | undefined, extra: Partial<EpochRow> = {}): EpochRow | null {
  if (value == null || !Number.isFinite(value)) return null
  const cid = canonicalId(id)
  return { startTs, dataTypeId: cid, dataTypeName: NAMES[cid] ?? String(cid), value, valueType: Number.isInteger(value) ? "LONG" : "DOUBLE", ...extra }
}

export const compact = <R>(rows: (R | null)[]): R[] => rows.filter((r): r is R => r != null)

/** Several daily rows for one day from a `{ catalogueId: value }` map (nulls/NaN dropped). */
export function dailyMap(day: string, map: Record<number, number | null | undefined>, extra: Partial<DailyRow> = {}): DailyRow[] {
  return compact(Object.entries(map).map(([id, v]) => daily(day, Number(id), v, extra)))
}

/** A DATE-typed daily row: the instant as unix seconds in `value`, ISO in `valueText`. */
export function dailyDate(day: string, id: number, iso: string | null | undefined, extra: Partial<DailyRow> = {}): DailyRow | null {
  if (!iso) return null
  const t = Date.parse(iso)
  if (!Number.isFinite(t)) return null
  const cid = canonicalId(id)
  return { day, dataTypeId: cid, dataTypeName: NAMES[cid] ?? String(cid), value: Math.round(t / 1000), valueText: new Date(t).toISOString(), valueType: "DATE", ...extra }
}

/** A STRING-typed daily row (categorical vendor values: Polar recharge status, Suunto stress state…). */
export function dailyText(day: string, id: number, text: string | null | undefined, extra: Partial<DailyRow> = {}): DailyRow | null {
  if (!text) return null
  const cid = canonicalId(id)
  return { day, dataTypeId: cid, dataTypeName: NAMES[cid] ?? String(cid), value: null, valueText: text, valueType: "STRING", ...extra }
}

export const num = (v: unknown): number | null => {
  if (v == null || v === "") return null
  const n = typeof v === "number" ? v : Number(v)
  return Number.isFinite(n) ? n : null
}
export const mean = (xs: (number | null | undefined)[]): number | null => {
  const v = xs.filter((x): x is number => typeof x === "number" && Number.isFinite(x))
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null
}
/** Parses `+02:00` / `-0530` / `Z` into minutes; null when absent. */
export function offsetMinutes(s: string | null | undefined): number | null {
  if (!s) return null
  if (s === "Z") return 0
  const m = /([+-])(\d{2}):?(\d{2})/.exec(s)
  return m ? (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3])) : null
}
/** The vendor-local day of an ISO timestamp: honours the offset embedded in the string (or `offsetMin`). */
export function dayOfISO(iso: string, offsetMin?: number | null): string {
  const t = Date.parse(iso)
  const off = offsetMin ?? offsetMinutes(iso.slice(19)) ?? 0
  return localDay(new Date(t), off)
}
export const dayStartISO = (day: string) => `${day}T00:00:00Z`
export const dayEndISO = (day: string) => `${addDays(day, 1)}T00:00:00Z`
export const unixOf = (iso: string) => Math.round(Date.parse(iso) / 1000)

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

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes))
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))
export const b64url = (bytes: Uint8Array) => b64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")

/** `WEARABLE_TOKEN_KEY` is version 1; `WEARABLE_TOKEN_KEY_V<n>` the later ones. The writer uses `WEARABLE_TOKEN_KEY_VERSION`. */
export function keyEnvName(version: number): string { return version === 1 ? "WEARABLE_TOKEN_KEY" : `WEARABLE_TOKEN_KEY_V${version}` }
export function currentKeyVersion(): number { return Math.max(1, Number(Deno.env.get("WEARABLE_TOKEN_KEY_VERSION") ?? "1") || 1) }

const keyCache = new Map<number, Promise<CryptoKey>>()
function aesKey(version: number): Promise<CryptoKey> {
  let p = keyCache.get(version)
  if (!p) {
    p = (async () => {
      const raw = unb64(env(keyEnvName(version)))
      if (raw.length !== 32) throw new Error(`${keyEnvName(version)} must be 32 bytes base64`)
      return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"])
    })()
    keyCache.set(version, p)
  }
  return p
}
/** Tests inject keys without the environment. */
export function _setKeyForTests(version: number, raw32: Uint8Array<ArrayBuffer>): void {
  keyCache.set(version, crypto.subtle.importKey("raw", raw32, "AES-GCM", false, ["encrypt", "decrypt"]))
}

export type TokenType = "access" | "refresh" | "verifier" | "webhook"
/** What a ciphertext is bound to: a blob moved to another row, vendor or column fails to decrypt. */
export interface TokenAAD { accountId: string; vendor: string; tokenType: TokenType }
const aadBytes = (a: TokenAAD, version: number) => new TextEncoder().encode(`${a.accountId}|${a.vendor}|${a.tokenType}|${version}`)

/** `v2.<keyVersion>.<base64(iv‖ciphertext)>` with the AAD above. */
export async function encrypt(text: string, aad: TokenAAD, version = currentKeyVersion()): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: aadBytes(aad, version) }, await aesKey(version), new TextEncoder().encode(text)))
  const out = new Uint8Array(iv.length + ct.length); out.set(iv); out.set(ct, iv.length)
  return `v2.${version}.${b64(out)}`
}

/** Decrypts v2 (AAD-bound) and legacy v1 (key 1, no AAD) blobs. */
export async function decrypt(blob: string, aad: TokenAAD): Promise<string> {
  let version = 1, payload: string, additionalData: Uint8Array | undefined
  if (blob.startsWith("v1.")) { payload = blob.slice(3) }
  else if (blob.startsWith("v2.")) {
    const [, v, p] = blob.split(".")
    version = Number(v); payload = p ?? ""
    if (!Number.isInteger(version) || version < 1 || !payload) throw new Error("malformed token blob")
    additionalData = aadBytes(aad, version)
  } else throw new Error("unknown token blob version")
  const bytes = unb64(payload)
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12), ...(additionalData ? { additionalData } : {}) }, await aesKey(version), bytes.slice(12))
  return new TextDecoder().decode(pt)
}

export const blobKeyVersion = (blob: string | null | undefined): number | null => {
  if (!blob) return null
  if (blob.startsWith("v1.")) return 1
  const m = /^v2\.(\d+)\./.exec(blob)
  return m ? Number(m[1]) : null
}

export function randomToken(bytes = 32): string { return b64url(crypto.getRandomValues(new Uint8Array(bytes))) }

export async function sha256Hex(data: string | Uint8Array<ArrayBuffer>): Promise<string> {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("")
}

export async function pkceChallenge(verifier: string): Promise<string> {
  return b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))))
}

export async function hmacSha256(secret: string, data: string, encoding: "hex" | "base64" = "hex"): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data)))
  if (encoding === "base64") return b64(sig)
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("")
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let r = 0
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return r === 0
}

// MARK: - Vendor HTTP + the error taxonomy

export class UnauthorizedError extends Error { status = 401; constructor(m: string) { super("unauthorized: " + m); this.name = "UnauthorizedError" } }
export class RateLimitedError extends Error { status = 429; retryAfter: number; constructor(h: string | null) { super("rate limited"); this.name = "RateLimitedError"; this.retryAfter = Math.min(3600, Number(h ?? 60) || 60) } }
export class VendorHttpError extends Error { status: number; constructor(status: number, m: string) { super(`vendor ${status}: ${m}`); this.name = "VendorHttpError"; this.status = status } }
export class TokenEndpointError extends Error { status: number; oauthError: string | null; constructor(status: number, body: string) { super(`token endpoint ${status}: ${body.slice(0, 200)}`); this.name = "TokenEndpointError"; this.status = status; this.oauthError = /"error"\s*:\s*"([^"]+)"/.exec(body)?.[1] ?? null } }
export class ReconnectRequiredError extends Error { constructor(m = "reconnect required") { super(m); this.name = "ReconnectRequiredError" } }
export class VendorPausedError extends Error { constructor(v: string) { super(`vendor ${v} paused`); this.name = "VendorPausedError" } }
export class NoAccountError extends Error { constructor() { super("no connected account"); this.name = "NoAccountError" } }

export type ErrorCode = "rate_limited" | "unauthorized" | "reconnect_required" | "vendor_paused" | "vendor_5xx" | "vendor_4xx" | "network" | "no_account" | "token_conflict" | "unknown"
export interface Classified { code: ErrorCode; retry: boolean; delaySeconds: number; accountStatus?: "reconnect_required" | "degraded" | "error" }

export const MAX_ATTEMPTS = 8
/** `min(15 min, 2^attempt · 5 s)` plus up to 5 s of jitter. */
export function backoffSeconds(attempt: number, jitter = Math.random()): number {
  return Math.min(900, Math.pow(2, Math.max(0, attempt)) * 5) + Math.floor(jitter * 5)
}

/** Maps a thrown error to what the queue should do with the job and the account. Pure. */
export function classifyError(e: unknown, attempt: number, jitter?: number): Classified {
  if (e instanceof RateLimitedError) return { code: "rate_limited", retry: true, delaySeconds: e.retryAfter }
  if (e instanceof ReconnectRequiredError) return { code: "reconnect_required", retry: false, delaySeconds: 0, accountStatus: "reconnect_required" }
  if (e instanceof UnauthorizedError) return { code: "unauthorized", retry: false, delaySeconds: 0, accountStatus: "reconnect_required" }
  if (e instanceof VendorPausedError) return { code: "vendor_paused", retry: true, delaySeconds: 3600 }
  if (e instanceof NoAccountError) return { code: "no_account", retry: false, delaySeconds: 0 }
  if (e instanceof VendorHttpError) {
    if (e.status >= 500) return { code: "vendor_5xx", retry: true, delaySeconds: backoffSeconds(attempt, jitter), accountStatus: "degraded" }
    return { code: "vendor_4xx", retry: false, delaySeconds: 0, accountStatus: "error" }
  }
  const name = (e as { name?: string })?.name ?? ""
  if (name === "TypeError" || name === "AbortError" || /network|fetch failed|connection/i.test(String((e as Error)?.message ?? ""))) {
    return { code: "network", retry: true, delaySeconds: backoffSeconds(attempt, jitter), accountStatus: "degraded" }
  }
  if (/token_conflict/.test(String((e as Error)?.message ?? ""))) return { code: "token_conflict", retry: true, delaySeconds: 30 }
  return { code: "unknown", retry: attempt < 3, delaySeconds: backoffSeconds(attempt, jitter), accountStatus: "error" }
}

/** OAuth token endpoint POST with either Basic client auth or client credentials in the body. */
export async function tokenPost(url: string, params: Record<string, string>, auth: { basic?: { id: string; secret: string }; headers?: Record<string, string> } = {}): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json", ...(auth.headers ?? {}) }
  if (auth.basic) headers.Authorization = "Basic " + btoa(`${auth.basic.id}:${auth.basic.secret}`)
  const resp = await fetch(url, { method: "POST", headers, body: new URLSearchParams(params) })
  const text = await resp.text()
  if (!resp.ok) throw new TokenEndpointError(resp.status, text)
  return JSON.parse(text)
}

export async function getJSON(url: string, headers: Record<string, string>): Promise<Record<string, unknown>> {
  const resp = await fetch(url, { headers: { Accept: "application/json", ...headers } })
  const text = await resp.text()
  if (resp.status === 401) throw new UnauthorizedError(text.slice(0, 200))
  if (resp.status === 429) throw new RateLimitedError(resp.headers.get("Retry-After"))
  if (!resp.ok) throw new VendorHttpError(resp.status, `GET ${url.split("?")[0]}: ${text.slice(0, 300)}`)
  return text ? JSON.parse(text) : {}
}

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

/** Kill switch: `wearable_vendors.status = 'paused'` stops every outbound call without touching tokens. */
export async function vendorStatus(db: SupabaseClient, vendor: VendorKey): Promise<"planned" | "available" | "paused" | "unknown"> {
  const { data } = await db.from("wearable_vendors").select("status").eq("key", vendor).maybeSingle()
  return (data?.status as "planned" | "available" | "paused" | undefined) ?? "unknown"
}
export async function assertVendorActive(db: SupabaseClient, vendor: VendorKey): Promise<void> {
  if ((await vendorStatus(db, vendor)) === "paused") throw new VendorPausedError(vendor)
}

// MARK: - Accounts (wearable_vendor_accounts)

export type AccountStatus = "not_connected" | "connecting" | "connected" | "syncing" | "degraded" | "reconnect_required" | "revoked" | "disconnected" | "error"
export const LIVE_STATUSES: AccountStatus[] = ["connected", "syncing", "degraded"]

export interface AccountRow {
  id: string
  patient_id: string
  vendor: VendorKey
  vendor_user_id: string | null
  access_token_enc: string | null
  refresh_token_enc: string | null
  token_expires_at: string | null
  scopes: string[] | null
  status: AccountStatus
  meta: Record<string, unknown> | null
  token_version: number
  token_key_version: number
  reconnect_required: boolean
  granted_scopes: string[] | null
  last_error_code: string | null
  last_error: string | null
  last_sync_at: string | null
  last_successful_sync_at: string | null
}

export const isLive = (a: Pick<AccountRow, "status"> | null | undefined) => !!a && LIVE_STATUSES.includes(a.status)

export async function loadAccount(db: SupabaseClient, id: string): Promise<AccountRow | null> {
  const { data } = await db.from("wearable_vendor_accounts").select("*").eq("id", id).maybeSingle()
  return (data as AccountRow | null) ?? null
}

export async function findAccount(db: SupabaseClient, patientId: string, vendor: VendorKey): Promise<AccountRow | null> {
  const { data } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", patientId).eq("vendor", vendor).maybeSingle()
  return (data as AccountRow | null) ?? null
}

/** The row for (patient, vendor), created as `connecting` when absent — the id is what the token AAD binds to. */
export async function ensureAccount(db: SupabaseClient, patientId: string, vendor: VendorKey): Promise<AccountRow> {
  const existing = await findAccount(db, patientId, vendor)
  if (existing) return existing
  const { data, error } = await db.from("wearable_vendor_accounts").insert({ patient_id: patientId, vendor, status: "connecting" }).select("*").single()
  if (error) throw new Error(`account insert: ${error.message}`)
  return data as AccountRow
}

export class TokenConflictError extends Error { constructor() { super("token_conflict: the account changed underneath"); this.name = "TokenConflictError" } }

/**
 * Encrypts and stores a token set on an existing account with compare-and-swap on `token_version`.
 * Throws TokenConflictError when another worker wrote first (the caller re-reads).
 */
export async function storeTokens(db: SupabaseClient, account: AccountRow, tokens: TokenSet, patch: { vendorUserId?: string | null; meta?: Record<string, unknown> | null; status?: AccountStatus; grantedScopes?: string[] | null } = {}): Promise<AccountRow> {
  const version = currentKeyVersion()
  const row: Record<string, unknown> = {
    access_token_enc: await encrypt(tokens.accessToken, { accountId: account.id, vendor: account.vendor, tokenType: "access" }, version),
    // A refresh token is REPLACED when the vendor sends one and KEPT when the reply omits it (Google, Withings
    // and others only return it on the first consent); it is cleared only by disconnect/revoke paths.
    ...(tokens.refreshToken
      ? { refresh_token_enc: await encrypt(tokens.refreshToken, { accountId: account.id, vendor: account.vendor, tokenType: "refresh" }, version) }
      : account.refresh_token_enc && account.token_key_version !== version
        ? { refresh_token_enc: await encrypt((await decodeTokens(account)).refreshToken ?? "", { accountId: account.id, vendor: account.vendor, tokenType: "refresh" }, version) }
        : {}),
    token_expires_at: tokens.expiresAt ? new Date(tokens.expiresAt * 1000).toISOString() : null,
    scopes: tokens.scopes ?? account.scopes ?? null,
    token_version: Number(account.token_version ?? 1) + 1,
    token_key_version: version,
    refresh_lock_owner: null, refresh_lock_until: null,
    reconnect_required: false, last_error: null, last_error_code: null,
    updated_at: new Date().toISOString(),
  }
  if (patch.vendorUserId !== undefined) row.vendor_user_id = patch.vendorUserId
  if (patch.meta !== undefined) row.meta = patch.meta
  if (patch.grantedScopes !== undefined) row.granted_scopes = patch.grantedScopes
  if (patch.status) { row.status = patch.status; if (patch.status === "connected") { row.revoked_at = null; row.disconnected_at = null; row.connected_at = new Date().toISOString() } }
  const { data, error } = await db.from("wearable_vendor_accounts").update(row).eq("id", account.id).eq("token_version", account.token_version ?? 1).select("*")
  if (error) throw new Error(`account update: ${error.message}`)
  if (!data?.length) throw new TokenConflictError()
  return data[0] as AccountRow
}

export async function decodeTokens(account: AccountRow): Promise<TokenSet> {
  if (!account.access_token_enc) throw new UnauthorizedError("no token")
  return {
    accessToken: await decrypt(account.access_token_enc, { accountId: account.id, vendor: account.vendor, tokenType: "access" }),
    refreshToken: account.refresh_token_enc ? await decrypt(account.refresh_token_enc, { accountId: account.id, vendor: account.vendor, tokenType: "refresh" }) : undefined,
    expiresAt: account.token_expires_at ? Math.floor(new Date(account.token_expires_at).getTime() / 1000) : undefined,
    scopes: account.scopes ?? undefined,
  }
}

const REFRESH_AHEAD_S = 120
const needsRefresh = (a: AccountRow) => !!a.token_expires_at && new Date(a.token_expires_at).getTime() / 1000 < Date.now() / 1000 + REFRESH_AHEAD_S
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const isTerminalRefresh = (e: unknown) => e instanceof UnauthorizedError || (e instanceof TokenEndpointError && (e.status === 401 || (e.status === 400 && (e.oauthError === "invalid_grant" || e.oauthError === "invalid_token"))))

/**
 * Live tokens for an account. Refreshes when within 2 minutes of expiry (or `force`), under the DB lease
 * `wearable_token_lock` with a `token_version` CAS: when another worker refreshed meanwhile, its tokens are
 * used. A terminal refresh failure (invalid_grant / 401) marks the account `reconnect_required`.
 */
export async function liveTokens(db: SupabaseClient, account: AccountRow, adapter: VendorAdapter, opts: { force?: boolean } = {}): Promise<{ tokens: TokenSet; account: AccountRow }> {
  let acc = account
  if (!opts.force && !needsRefresh(acc)) return { tokens: await decodeTokens(acc), account: acc }
  const owner = crypto.randomUUID()
  const startVersion = acc.token_version
  for (let attempt = 0; attempt < 8; attempt++) {
    const { data: got } = await db.rpc("wearable_token_lock", { p_account: acc.id, p_owner: owner, p_seconds: 30 })
    if (got === true) {
      try {
        acc = (await loadAccount(db, acc.id)) ?? acc
        if (acc.token_version !== startVersion && !needsRefresh(acc)) return { tokens: await decodeTokens(acc), account: acc }  // someone refreshed first
        const current = await decodeTokens(acc)
        if (!current.refreshToken) throw new UnauthorizedError("expired, no refresh token")
        let fresh: TokenSet
        try { fresh = await adapter.refresh(current.refreshToken) }
        catch (e) {
          if (isTerminalRefresh(e)) {
            await markAccount(db, acc.id, { status: "reconnect_required", reconnect_required: true, last_error_code: "refresh_rejected", last_error: String((e as Error).message ?? e).slice(0, 200), refresh_lock_owner: null, refresh_lock_until: null })
            await audit(db, { patientId: acc.patient_id, vendor: acc.vendor, accountId: acc.id, action: "token_refresh_failed", details: { code: "refresh_rejected" } })
            throw new ReconnectRequiredError()
          }
          throw e
        }
        const merged: TokenSet = { ...current, ...fresh, refreshToken: fresh.refreshToken ?? current.refreshToken, scopes: fresh.scopes ?? current.scopes }
        acc = await storeTokens(db, acc, merged)
        log("info", "token.refreshed", { fn: "core", vendor: acc.vendor, account: acc.id })
        return { tokens: merged, account: acc }
      } catch (e) {
        if (e instanceof TokenConflictError) { acc = (await loadAccount(db, acc.id)) ?? acc; continue }
        throw e
      } finally {
        await db.from("wearable_vendor_accounts").update({ refresh_lock_owner: null, refresh_lock_until: null }).eq("id", acc.id).eq("refresh_lock_owner", owner)
      }
    }
    await sleep(300 * (attempt + 1))
    acc = (await loadAccount(db, acc.id)) ?? acc
    if (acc.token_version !== startVersion && !needsRefresh(acc)) return { tokens: await decodeTokens(acc), account: acc }
    if (acc.status === "reconnect_required") throw new ReconnectRequiredError()
  }
  throw new TokenConflictError()
}

/**
 * Runs a vendor call with live tokens: a 401 triggers ONE forced refresh and ONE retry; a second 401 marks
 * the account `reconnect_required`. The kill switch is checked first.
 */
export async function withVendorCall<R>(db: SupabaseClient, account: AccountRow, adapter: VendorAdapter, fn: (tokens: TokenSet, account: AccountRow) => Promise<R>): Promise<R> {
  await assertVendorActive(db, account.vendor)
  let live = await liveTokens(db, account, adapter)
  try { return await fn(live.tokens, live.account) }
  catch (e) {
    if (!(e instanceof UnauthorizedError)) throw e
    log("warn", "vendor.401_retry", { fn: "core", vendor: account.vendor, account: account.id })
    live = await liveTokens(db, live.account, adapter, { force: true })
    try { return await fn(live.tokens, live.account) }
    catch (e2) {
      if (e2 instanceof UnauthorizedError) {
        await markAccount(db, account.id, { status: "reconnect_required", reconnect_required: true, last_error_code: "unauthorized_after_refresh" })
        await audit(db, { patientId: account.patient_id, vendor: account.vendor, accountId: account.id, action: "reconnect_required", details: { code: "unauthorized_after_refresh" } })
        throw new ReconnectRequiredError()
      }
      throw e2
    }
  }
}

/** Re-encrypts an account's tokens under the current key version (rotation path): decrypt old → encrypt new → CAS. */
export async function rotateAccountTokens(db: SupabaseClient, account: AccountRow): Promise<boolean> {
  if (!account.access_token_enc || account.token_key_version === currentKeyVersion()) return false
  const tokens = await decodeTokens(account)
  await storeTokens(db, account, tokens)
  await audit(db, { patientId: account.patient_id, vendor: account.vendor, accountId: account.id, action: "token_key_rotated", details: { from: account.token_key_version, to: currentKeyVersion() } })
  return true
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

/** One line in `wearable_audit_log`. `details` must never carry tokens, codes or health values. */
export async function audit(db: SupabaseClient, e: { patientId: string | null; vendor: VendorKey | string; accountId?: string | null; action: string; actor?: "member" | "system" | "cron" | "vendor" | "practitioner"; details?: Record<string, unknown> | null }) {
  const { error } = await db.from("wearable_audit_log").insert({ patient_id: e.patientId, vendor: e.vendor, account_id: e.accountId ?? null, action: e.action, actor: e.actor ?? "system", details: e.details ?? null })
  if (error) log("warn", "audit.insert_failed", { fn: "core", vendor: e.vendor, action: e.action, message: error.message })
}

// MARK: - Rows → tables

/** Upserts on the natural keys with provenance; a re-issued epoch (same source_record_id, moved start) supersedes the old row. */
export async function persistRows(db: SupabaseClient, patientId: string, vendor: VendorKey, rows: RowBatch, rawEventId: string | null, accountId?: string | null) {
  const sourceId = VENDOR_SOURCE_IDS[vendor]
  const prov = (r: DailyRow | EpochRow) => ({
    source_connection_id: accountId ?? null, source_resource_type: r.sourceResourceType ?? null, source_record_id: r.sourceRecordId ?? null,
    source_field: r.sourceField ?? null, source_device_id: r.sourceDeviceId ?? null, source_modified_at: r.sourceModifiedAt ?? null,
    normalization_version: NORMALIZATION_VERSION, source_offset_minutes: r.timezoneOffset ?? null, local_date_basis: "vendor_local",
  })
  const dailyRows = rows.daily.map((d) => ({
    patient_id: patientId, data_source_id: sourceId, day: d.day, data_type_id: canonicalId(d.dataTypeId), data_type_name: NAMES[canonicalId(d.dataTypeId)] ?? d.dataTypeName,
    value: d.value, value_text: d.valueText ?? null, value_type: d.valueType ?? null, timezone_offset: d.timezoneOffset ?? null,
    details: d.details ?? null, raw_event_id: rawEventId, recorded_at: d.recordedAt ?? null, ...prov(d),
  }))
  const epochRows = rows.epoch.map((e) => ({
    patient_id: patientId, data_source_id: sourceId, data_type_id: canonicalId(e.dataTypeId), data_type_name: NAMES[canonicalId(e.dataTypeId)] ?? e.dataTypeName,
    value: e.value, value_text: e.valueText ?? null, value_type: e.valueType ?? null, start_ts: e.startTs, end_ts: e.endTs ?? null,
    timezone_offset: e.timezoneOffset ?? null, details: e.details ?? null, raw_event_id: rawEventId, ...prov(e),
  }))
  // Dedupe inside the batch on the natural keys (PostgREST refuses duplicate conflict targets in one upsert).
  const seenD = new Set<string>(); const uniqD = dailyRows.filter((r) => { const k = `${r.day}|${r.data_type_id}`; if (seenD.has(k)) return false; seenD.add(k); return true })
  const seenE = new Set<string>(); const uniqE = epochRows.filter((r) => { const k = `${r.data_type_id}|${r.start_ts}`; if (seenE.has(k)) return false; seenE.add(k); return true })
  for (let i = 0; i < uniqD.length; i += 500) {
    const { error } = await db.from("wearable_daily").upsert(uniqD.slice(i, i + 500), { onConflict: "patient_id,data_source_id,day,data_type_id" })
    if (error) throw new Error(`daily upsert: ${error.message}`)
  }
  const inserted: { id: string; data_type_id: number; start_ts: string; source_record_id: string | null }[] = []
  for (let i = 0; i < uniqE.length; i += 500) {
    const { data, error } = await db.from("wearable_epoch").upsert(uniqE.slice(i, i + 500), { onConflict: "patient_id,data_source_id,data_type_id,start_ts" }).select("id,data_type_id,start_ts,source_record_id")
    if (error) throw new Error(`epoch upsert: ${error.message}`)
    inserted.push(...((data ?? []) as typeof inserted))
  }
  await supersedeMovedEpochs(db, patientId, sourceId, inserted)
  return { daily: uniqD.length, epoch: uniqE.length }
}

/** A vendor record that moved (same source_record_id, new start_ts) leaves its old row pointing at the new one. */
async function supersedeMovedEpochs(db: SupabaseClient, patientId: string, sourceId: number, fresh: { id: string; data_type_id: number; start_ts: string; source_record_id: string | null }[]) {
  const withIds = fresh.filter((r) => r.source_record_id)
  if (!withIds.length) return
  const { data: old } = await db.from("wearable_epoch").select("id,data_type_id,start_ts,source_record_id")
    .eq("patient_id", patientId).eq("data_source_id", sourceId).is("superseded_by", null)
    .in("source_record_id", [...new Set(withIds.map((r) => r.source_record_id as string))])
  for (const o of (old ?? []) as typeof fresh) {
    const n = withIds.find((r) => r.source_record_id === o.source_record_id && r.data_type_id === o.data_type_id)
    if (n && n.id !== o.id && Date.parse(n.start_ts) !== Date.parse(o.start_ts)) {
      await db.from("wearable_epoch").update({ superseded_by: n.id }).eq("id", o.id)
    }
  }
}

export type RawKind = "oauth_callback" | "vendor_webhook" | "vendor_api"
export async function storeRaw(db: SupabaseClient, patientId: string | null, vendor: VendorKey, kind: RawKind, payload: unknown, opts: { vendorUserId?: string | null; payloadHash?: string | null; vendorEventId?: string | null; retentionDays?: number | null } = {}): Promise<string | null> {
  const days = opts.retentionDays ?? (Number(Deno.env.get("WEARABLE_RAW_RETENTION_DAYS") ?? "") || null)
  const { data, error } = await db.from("wearable_raw_events").insert({
    patient_id: patientId, provider: vendor, end_user_id: opts.vendorUserId ?? null, kind, payload,
    payload_hash: opts.payloadHash ?? null, vendor_event_id: opts.vendorEventId ?? null,
    retention_class: days ? "standard" : "keep", delete_after: days ? new Date(Date.now() + days * 86_400_000).toISOString() : null,
  }).select("id").single()
  if (error) { log("error", "raw.insert_failed", { fn: "core", vendor, kind, message: error.message }); return null }
  return data?.id ?? null
}

export type SyncKind = "notification" | "backfill" | "reconcile" | "manual" | "push"
export interface EnqueueArgs {
  patientId: string | null; vendor: VendorKey; vendorUserId: string; kind: string; syncKind: SyncKind
  windowStart?: string; windowEnd?: string; rawEventId?: string | null; dedupeKey?: string | null; priority?: number; accountId?: string | null
}
/** Inserts a job through `wearable_queue_enqueue` (dedupe on the active key). Returns the id, or null when an identical job is active. */
export async function enqueue(db: SupabaseClient, a: EnqueueArgs): Promise<string | null> {
  const dedupe = a.dedupeKey === undefined ? `${a.syncKind}:${a.vendor}:${a.patientId ?? a.vendorUserId}:${a.windowStart ?? ""}:${a.windowEnd ?? ""}` : a.dedupeKey
  const { data, error } = await db.rpc("wearable_queue_enqueue", {
    p_patient: a.patientId, p_vendor: a.vendor, p_end_user: a.vendorUserId, p_kind: a.kind, p_sync_kind: a.syncKind,
    p_window_start: a.windowStart ? `${a.windowStart}T00:00:00Z` : null, p_window_end: a.windowEnd ? `${a.windowEnd}T23:59:59Z` : null,
    p_raw_event: a.rawEventId ?? null, p_dedupe_key: dedupe, p_priority: a.priority ?? 0, p_account: a.accountId ?? null, p_source_id: VENDOR_SOURCE_IDS[a.vendor],
  })
  if (error) { log("error", "queue.enqueue_failed", { fn: "core", vendor: a.vendor, message: error.message }); return null }
  return (data as string | null) ?? null
}

/** Cancels every active job of (patient, vendor) — disconnect, erase. */
export async function cancelJobs(db: SupabaseClient, patientId: string, vendor: VendorKey, reason: string) {
  await db.from("wearable_sync_queue").update({ status: "cancelled", last_error_code: reason }).eq("patient_id", patientId).eq("vendor", vendor).in("status", ["pending", "processing"])
}

// MARK: - Webhook receipts

/** First dedupe key available: the vendor's event id, else the body hash (with the event index for multi-event bodies). */
export function receiptKey(ev: Pick<WebhookEvent, "eventId">, bodyHash: string, index: number): string {
  return ev.eventId ? `evt:${ev.eventId}` : `hash:${bodyHash}#${index}`
}

/** Records a receipt; false = this event was already accepted (duplicate delivery), the caller ACKs and skips. */
export async function recordReceipt(db: SupabaseClient, vendor: VendorKey, key: string, bodyHash: string, eventId: string | null, rawEventId: string | null): Promise<boolean> {
  const { error } = await db.from("wearable_webhook_receipts").insert({ vendor, dedupe_key: key, payload_hash: bodyHash, vendor_event_id: eventId, raw_event_id: rawEventId })
  if (!error) return true
  if (error.code === "23505") return false
  log("warn", "receipt.insert_failed", { fn: "core", vendor, message: error.message })
  return true  // never drop an event because the receipt table hiccupped
}
