// Google Health API v4 (the Fitbit successor) — strategy 2026-09-14 Phase 2, decisions D4 (HRV ids) and D10
// (secret names). Corpus authority: research/…/vendors/google-fitbit.md (§6 OAuth, §7–8 tokens, §9 identity,
// §10–11 webhooks + Tink/ECDSA, §17 reconcile, §18/§20 HRV, §25 disconnect) + metrics/hrv-semantics.md,
// pack 07_HRV.md ("Google Health — strong mapping"), 12_TEMPERATURE.md, security/webhook-verification.md.
// ⚠ Deferred: restricted-scope verification + CASA assessment gate real consent (`wearable_vendors.status` = `planned`).
//
// What this adapter guarantees:
//   • OAuth: web-server flow with the client secret; PKCE `supported` (corpus §6: "PKCE support follows Google
//     OAuth … the backend client secret remains required"). NO `prompt=consent` by default — the corpus says
//     "only when needed for a new refresh token/re-consent; do not annoy returning users"; the first grant of
//     an `access_type=offline` client already shows consent and returns the refresh token. Callers that know
//     they are re-linking a dead grant use `googleAuthorizeURL(p, { forceConsent: true })`.
//   • Scopes: activity_and_fitness, health_metrics_and_measurements, sleep, profile (§6). The former `settings`
//     scope is not in the corpus and is gone.
//   • Refresh: adopts a rotated `refresh_token` when Google returns one, keeps the old one otherwise (§8).
//   • Webhooks (§10–11, D10): `Authorization: Bearer <GOOGLE_WEBHOOK_SECRET>` (constant-time) AND the
//     `GOOGLE-HEALTH-API-SIGNATURE` header verified over the EXACT raw body bytes against Google's published
//     Tink public keyset (ECDSA P-256 / SHA-256, WebCrypto). Fail closed: anything unverifiable throws → 401.
//   • HRV (D4, §18/§20, 07_HRV): `heart-rate-variability` RMSSD → 3100 (epoch), SDNN field → 3112;
//     `daily-heart-rate-variability` average → 3100 (daily, window "daily_aggregate"). 3106 is NEVER written.
//   • Provenance: every row carries `sourceRecordId` + `sourceResourceType` (+ version / lastModified / device).
//   • Reconcile: nightly 3 d, weekly 14 d (§17 says a 30-day weekly pass; 14 keeps the weekly window inside
//     the 14-day limit the corpus §13 documents for HR/calorie-derived rollups — widen once rollups are split).
import {
  type DailyRow, type EpochRow, type ExchangeResult, type TokenSet, type VendorAdapter, type WebhookEvent, T, UnauthorizedError, RateLimitedError, VendorHttpError,
  addDays, compact, dailyDate, dailyMap, daysBetween, dayOfISO, env, epoch, getJSON, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient,
} from "./core.ts"
import { log } from "./log.ts"

const AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN = "https://oauth2.googleapis.com/token"
const REVOKE = "https://oauth2.googleapis.com/revoke"
export const API = "https://health.googleapis.com/v4"
/** Corpus §11: Google's published Tink public keyset for webhook signatures (public verification data, not a secret). */
export const KEYSET_URL = "https://www.gstatic.com/googlehealthapi/webhooks/webhooks_public_keyset.json"
export const SIGNATURE_HEADER = "GOOGLE-HEALTH-API-SIGNATURE"
/** VERIFY: the corpus says "keys rotate periodically, cache with refresh" without a TTL; 1 h + a forced refetch on an unknown key id. */
export const KEYSET_TTL_MS = 60 * 60 * 1000
const KEYSET_MIN_REFETCH_MS = 60 * 1000
const FN = "google"

const SCOPE_NAMES = ["activity_and_fitness", "health_metrics_and_measurements", "sleep", "profile"]
const SCOPES = SCOPE_NAMES.map((s) => `https://www.googleapis.com/auth/googlehealth.${s}.readonly`)

/** Data types the project-level subscriber asks for (corpus §10 `subscriberConfigs`). VERIFY the exact enum/strings against the v4 subscriber reference. */
export const SUBSCRIBER_DATA_TYPES = ["sleep", "heart-rate-variability", "daily-heart-rate-variability", "daily-resting-heart-rate", "daily-oxygen-saturation", "daily-respiratory-rate", "daily-sleep-temperature-derivations", "daily-vo2-max", "steps", "distance", "active-energy-burned", "total-calories", "weight"]

// MARK: - OAuth

/** The authorize URL; `prompt` is omitted unless the caller forces consent (corpus §6). */
export function googleAuthorizeURL(p: { clientId: string; redirectUri: string; state: string; codeChallenge?: string }, opts: { forceConsent?: boolean } = {}): string {
  const q = new URLSearchParams({ client_id: p.clientId, redirect_uri: p.redirectUri, response_type: "code", scope: SCOPES.join(" "), access_type: "offline", include_granted_scopes: "true", state: p.state })
  if (p.codeChallenge) { q.set("code_challenge", p.codeChallenge); q.set("code_challenge_method", "S256") }
  if (opts.forceConsent) q.set("prompt", "consent")
  return `${AUTH}?${q}`
}

const expiresAt = (t: Record<string, unknown>) => Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600)
const scopesOf = (t: Record<string, unknown>) => typeof t.scope === "string" ? t.scope.split(" ").filter(Boolean) : undefined

// MARK: - Tink / ECDSA webhook signature (corpus §11, security/webhook-verification.md "Google Health API")

type TinkPrefix = "TINK" | "CRUNCHY" | "LEGACY" | "RAW"
type SigEncoding = "DER" | "IEEE_P1363" | "UNKNOWN"
export interface VerifyKey { keyId: number; prefix: TinkPrefix; encoding: SigEncoding; key: CryptoKey }

const b64decode = (s: string): Uint8Array<ArrayBuffer> => {
  const std = s.trim().replace(/-/g, "+").replace(/_/g, "/")
  const padded = std + "=".repeat((4 - std.length % 4) % 4)
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
}
const b64url = (b: Uint8Array): string => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")

/** Minimal protobuf reader — enough for Tink's `EcdsaPublicKey { version=1, params=2 { hash_type=1, curve=2, encoding=3 }, x=3, y=4 }`. */
function protoFields(bytes: Uint8Array): Map<number, (number | Uint8Array<ArrayBuffer>)[]> {
  const out = new Map<number, (number | Uint8Array<ArrayBuffer>)[]>()
  let i = 0
  const varint = (): number => { let r = 0, shift = 0; for (;;) { if (i >= bytes.length) throw new Error("proto: truncated varint"); const b = bytes[i++]; r += (b & 0x7f) * 2 ** shift; shift += 7; if (!(b & 0x80)) return r } }
  while (i < bytes.length) {
    const tag = varint(), field = tag >>> 3, wire = tag & 7
    let v: number | Uint8Array<ArrayBuffer>
    if (wire === 0) v = varint()
    else if (wire === 2) { const len = varint(); if (i + len > bytes.length) throw new Error("proto: truncated bytes"); v = bytes.slice(i, i + len); i += len }
    else if (wire === 1) { v = 0; i += 8 }
    else if (wire === 5) { v = 0; i += 4 }
    else throw new Error(`proto: wire type ${wire}`)
    out.set(field, [...(out.get(field) ?? []), v])
  }
  return out
}

/** Big-endian integer bytes → exactly 32 bytes (Tink may prepend a sign 0x00; short values are left-padded). */
function coord32(b: Uint8Array): Uint8Array<ArrayBuffer> {
  let s = 0
  while (s < b.length - 1 && b[s] === 0) s++
  const t = b.slice(s)
  if (t.length > 32) throw new Error("ecdsa: coordinate longer than 32 bytes")
  const out = new Uint8Array(32); out.set(t, 32 - t.length)
  return out
}

/** DER `SEQUENCE { INTEGER r, INTEGER s }` → IEEE P1363 `r||s` (64 bytes), what WebCrypto verifies. */
export function derToP1363(sig: Uint8Array): Uint8Array<ArrayBuffer> {
  if (sig[0] !== 0x30) throw new Error("der: not a sequence")
  let i = 2
  if (sig[1] & 0x80) i = 2 + (sig[1] & 0x7f)
  const int = (): Uint8Array<ArrayBuffer> => {
    if (sig[i++] !== 0x02) throw new Error("der: expected integer")
    let len = sig[i++]
    if (len & 0x80) { const n = len & 0x7f; len = 0; for (let k = 0; k < n; k++) len = len * 256 + sig[i++] }
    const v = sig.slice(i, i + len); i += len
    return coord32(v)
  }
  const r = int(), s = int()
  const out = new Uint8Array(64); out.set(r, 0); out.set(s, 32)
  return out
}

/**
 * Parses Google's keyset. Primary shape: a Tink JSON keyset (`{ primaryKeyId, key: [{ keyData: { typeUrl, value, keyMaterialType },
 * status, keyId, outputPrefixType }] }`, `value` = serialized `google.crypto.tink.EcdsaPublicKey`). Also accepts a JWKS
 * (`{ keys: [{ kty: "EC", crv: "P-256", x, y, kid }] }`) in case Google publishes that form. VERIFY against a live download.
 * Only ENABLED, P-256 / SHA-256 keys are kept; anything else is ignored (never trusted).
 */
export async function parseKeyset(json: unknown): Promise<VerifyKey[]> {
  const out: VerifyKey[] = []
  const j = (json ?? {}) as Record<string, unknown>
  const importXY = (x: Uint8Array, y: Uint8Array) => crypto.subtle.importKey("jwk", { kty: "EC", crv: "P-256", x: b64url(x), y: b64url(y), ext: true }, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"])
  for (const k of (Array.isArray(j.key) ? j.key : []) as Record<string, unknown>[]) {
    try {
      if (k.status !== "ENABLED") continue
      const kd = (k.keyData ?? {}) as Record<string, unknown>
      if (kd.typeUrl !== "type.googleapis.com/google.crypto.tink.EcdsaPublicKey") continue
      const f = protoFields(b64decode(String(kd.value ?? "")))
      const params = protoFields((f.get(2)?.[0] as Uint8Array) ?? new Uint8Array())
      const hash = params.get(1)?.[0], curve = params.get(2)?.[0], enc = params.get(3)?.[0]
      if (hash !== 3 /* SHA256 */ || curve !== 2 /* NIST_P256 */) continue
      const x = f.get(3)?.[0], y = f.get(4)?.[0]
      if (!(x instanceof Uint8Array) || !(y instanceof Uint8Array)) continue
      const prefix = String(k.outputPrefixType ?? "TINK") as TinkPrefix
      out.push({ keyId: Number(k.keyId), prefix: ["TINK", "CRUNCHY", "LEGACY", "RAW"].includes(prefix) ? prefix : "TINK", encoding: enc === 2 ? "DER" : enc === 1 ? "IEEE_P1363" : "UNKNOWN", key: await importXY(coord32(x), coord32(y)) })
    } catch (e) { log("warn", "google.keyset_key_skipped", { fn: FN, vendor: FN, message: String((e as Error).message ?? e).slice(0, 120) }) }
  }
  for (const k of (Array.isArray(j.keys) ? j.keys : []) as Record<string, unknown>[]) {
    try {
      if (k.kty !== "EC" || k.crv !== "P-256" || typeof k.x !== "string" || typeof k.y !== "string") continue
      out.push({ keyId: Number(k.kid) || 0, prefix: "RAW", encoding: "UNKNOWN", key: await importXY(b64decode(k.x), b64decode(k.y)) })
    } catch { /* skip */ }
  }
  return out
}

let keysetCache: { keys: VerifyKey[]; fetchedAt: number } | null = null

/** The cached keyset, refetched after KEYSET_TTL_MS (or on `force`, rate-limited to once a minute — key rotation). */
export async function keyset(force = false): Promise<VerifyKey[]> {
  const now = Date.now()
  if (keysetCache && !force && now - keysetCache.fetchedAt < KEYSET_TTL_MS) return keysetCache.keys
  if (keysetCache && force && now - keysetCache.fetchedAt < KEYSET_MIN_REFETCH_MS) return keysetCache.keys
  const r = await fetch(KEYSET_URL, { headers: { Accept: "application/json" } })
  if (!r.ok) throw new Error(`google keyset ${r.status}`)
  const keys = await parseKeyset(await r.json())
  if (!keys.length) throw new Error("google keyset: no usable P-256 key")
  keysetCache = { keys, fetchedAt: now }
  return keys
}

/**
 * Verifies one `GOOGLE-HEALTH-API-SIGNATURE` value over the raw bytes. Signature envelope = Tink output prefix
 * (`0x01`+keyId for TINK, `0x00`+keyId for CRUNCHY/LEGACY, none for RAW; keyId big-endian uint32) followed by the
 * ECDSA signature (DER per Tink's default ECDSA_P256 template, or IEEE P1363 — both handled). LEGACY signs body||0x00.
 * VERIFY: the header's text encoding is assumed base64 (standard or url-safe both decode).
 */
export async function verifySignature(body: Uint8Array<ArrayBuffer>, header: string, keys: VerifyKey[]): Promise<boolean> {
  let sig: Uint8Array<ArrayBuffer>
  try { sig = b64decode(header) } catch { return false }
  if (sig.length < 64) return false
  const prefixed = sig.length > 5 && (sig[0] === 0x01 || sig[0] === 0x00) ? ((sig[1] << 24) >>> 0) + (sig[2] << 16) + (sig[3] << 8) + sig[4] : null
  const legacyBody = () => { const b = new Uint8Array(body.length + 1); b.set(body); return b }
  for (const k of keys) {
    let raw: Uint8Array<ArrayBuffer>, msg: Uint8Array<ArrayBuffer> = body
    if (k.prefix === "RAW") raw = sig
    else {
      if (prefixed !== k.keyId || sig[0] !== (k.prefix === "TINK" ? 0x01 : 0x00)) continue
      raw = sig.slice(5)
      if (k.prefix === "LEGACY") msg = legacyBody()
    }
    let p1363: Uint8Array<ArrayBuffer>
    try { p1363 = raw[0] === 0x30 && raw.length !== 64 ? derToP1363(raw) : raw } catch { continue }
    if (p1363.length !== 64) continue
    try { if (await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, k.key, p1363, msg)) return true } catch { /* next key */ }
  }
  return false
}

async function verifyWebhookSignature(body: Uint8Array<ArrayBuffer>, header: string): Promise<void> {
  if (await verifySignature(body, header, await keyset())) return
  // Unknown key id / rotated key: refetch once (corpus §11 "keys rotate … cache with refresh"), then fail closed.
  if (await verifySignature(body, header, await keyset(true))) return
  throw new Error("google webhook signature invalid")
}

// MARK: - Notifications (corpus §10, §16)

interface Notification { vendorUserId: string; dataType: string; operation: string; eventId?: string; windowStart?: string; windowEnd?: string }

/** VERIFY: the batch envelope (top-level array vs `{ messages: [...] }`) and the per-message field names below are not pinned by the corpus. */
function notificationsOf(rawBody: string): Notification[] {
  if (!rawBody.trim()) return []
  const body = JSON.parse(rawBody) as unknown
  const list = Array.isArray(body) ? body : Array.isArray((body as Record<string, unknown>)?.messages) ? (body as Record<string, unknown[]>).messages : Array.isArray((body as Record<string, unknown>)?.notifications) ? (body as Record<string, unknown[]>).notifications : []
  const out: Notification[] = []
  for (const m of list as Record<string, unknown>[]) {
    const d = ((m.data ?? m) as Record<string, unknown>)
    if (!d?.healthUserId) continue
    const intervals = (d.intervals as { physicalTimeInterval?: { startTime?: string; endTime?: string } }[]) ?? []
    const starts = intervals.map((i) => i.physicalTimeInterval?.startTime).filter(Boolean) as string[], ends = intervals.map((i) => i.physicalTimeInterval?.endTime).filter(Boolean) as string[]
    const dataType = String(d.dataType ?? "unknown"), operation = String(d.operation ?? "UPSERT")
    const recordId = d.dataPointName ?? d.name ?? d.recordId ?? d.dataPointId ?? null, version = d.version ?? (d.metadata as Record<string, unknown> | undefined)?.version ?? null
    // VERIFY: the corpus names no message id field; `messageId`/`id` are tried, else the (user, dataType, record@version) triple.
    const eventId = typeof m.messageId === "string" ? m.messageId : typeof m.id === "string" ? m.id : recordId ? `${d.healthUserId}|${dataType}|${recordId}@${version ?? "-"}` : undefined
    out.push({ vendorUserId: String(d.healthUserId), dataType, operation, eventId, windowStart: starts.length ? starts.sort()[0].slice(0, 10) : undefined, windowEnd: ends.length ? ends.sort().at(-1)!.slice(0, 10) : undefined })
  }
  return out
}

// MARK: - API reads

const bearer = (tokens: TokenSet) => ({ Authorization: `Bearer ${tokens.accessToken}`, Accept: "application/json" })

async function gget(tokens: TokenSet, dt: string, filter: string, pageSize = 1000): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = []
  let pageToken = ""
  for (let i = 0; i < 20; i++) {
    const q = new URLSearchParams({ pageSize: String(pageSize), filter, ...(pageToken ? { pageToken } : {}) })
    const r = await fetch(`${API}/users/me/dataTypes/${dt}/dataPoints?${q}`, { headers: bearer(tokens) })
    if (r.status === 401) throw new UnauthorizedError("google 401")
    if (r.status === 403 || r.status === 404) return out          // scope not granted / type unavailable (corpus §24: not a retry)
    if (r.status === 429) throw new RateLimitedError(r.headers.get("Retry-After"))
    const text = await r.text()
    if (!r.ok) throw new VendorHttpError(r.status, `${dt}: ${text.slice(0, 200)}`)
    const j = text ? JSON.parse(text) : {}
    out.push(...((j.dataPoints as Record<string, unknown>[]) ?? []))
    pageToken = j.nextPageToken ?? ""
    if (!pageToken) break
  }
  return out
}

const ymd = (day: string) => ({ year: +day.slice(0, 4), month: +day.slice(5, 7), day: +day.slice(8, 10) })

async function rollup(tokens: TokenSet, dt: string, day: string): Promise<Record<string, unknown> | null> {
  const r = await fetch(`${API}/users/me/dataTypes/${dt}/dataPoints:dailyRollUp`, { method: "POST", headers: { ...bearer(tokens), "Content-Type": "application/json" }, body: JSON.stringify({ range: { start: ymd(day), end: ymd(addDays(day, 1)) }, windowSizeDays: 1 }) })
  if (r.status === 401) throw new UnauthorizedError("google 401")
  if (r.status === 429) throw new RateLimitedError(r.headers.get("Retry-After"))
  if (!r.ok) return null
  const j = await r.json()
  return (j.rollupDataPoints as Record<string, unknown>[])?.[0] ?? null
}

/** Provenance of one data point (corpus §16/§23: record id + version + last-modified + origin). VERIFY the envelope field names against v4. */
function prov(p: Record<string, unknown>, dt: string, fallbackId: string): Pick<DailyRow, "sourceRecordId" | "sourceResourceType" | "sourceModifiedAt" | "sourceDeviceId"> & { version: string | null } {
  const meta = (p.metadata ?? {}) as Record<string, unknown>, origin = (meta.dataOrigin ?? p.dataOrigin ?? {}) as Record<string, unknown>
  const id = p.name ?? p.dataPointId ?? p.id
  const modified = meta.lastModifiedTime ?? p.lastModifiedTime ?? p.updateTime ?? null
  return {
    sourceRecordId: id != null ? String(id) : fallbackId,
    sourceResourceType: dt,
    sourceModifiedAt: modified != null ? String(modified) : null,
    sourceDeviceId: origin.deviceId != null ? String(origin.deviceId) : p.device != null ? String(p.device) : null,
    version: meta.version != null ? String(meta.version) : p.version != null ? String(p.version) : null,
  }
}
const rollupProv = (dt: string, day: string) => ({ sourceRecordId: `rollup:${dt}:${day}`, sourceResourceType: dt })

// MARK: - The adapter

export const google: VendorAdapter = {
  key: "google",
  name: "Google Health",
  pkce: "supported",
  scopes: SCOPES,
  reconcile: { nightlyDays: 3, weeklyDays: 14 },

  authorizeURL(p) {
    return googleAuthorizeURL(p)
  },

  async exchangeCode({ code, redirectUri, codeVerifier }) {
    const { clientId, clientSecret } = vendorClient("google")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, ...(codeVerifier ? { code_verifier: codeVerifier } : {}) })
    // Corpus §9: `users.getIdentity` → `healthUserId` is the stable vendor_user_id; `legacyUserId` only as migration metadata.
    // VERIFY the REST path: the custom-method form `users/me:getIdentity` is used here.
    const id = await getJSON(`${API}/users/me:getIdentity`, { Authorization: `Bearer ${String(t.access_token)}` })
    const healthUserId = String(id.healthUserId ?? "")
    if (!healthUserId) throw new VendorHttpError(502, "getIdentity returned no healthUserId")
    return { accessToken: String(t.access_token), refreshToken: typeof t.refresh_token === "string" ? t.refresh_token : undefined, expiresAt: expiresAt(t), scopes: scopesOf(t), vendorUserId: healthUserId, raw: { legacy_user_id: id.legacyUserId ?? null } }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("google")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret })
    // Corpus §8: Google does not rotate on every refresh; adopt a replacement when one comes, keep the current one otherwise.
    const rotated = typeof t.refresh_token === "string" && t.refresh_token.length > 0 ? t.refresh_token : refreshToken
    return { accessToken: String(t.access_token), refreshToken: rotated, expiresAt: expiresAt(t), scopes: scopesOf(t) }
  },

  async revoke(tokens) {
    // Corpus §25: Google's OAuth revocation endpoint; revoking the refresh token drops the whole grant.
    await fetch(REVOKE, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ token: tokens.refreshToken ?? tokens.accessToken }) })
  },

  // `unsubscribe` is deliberately NOT implemented: the Google Health subscriber is PROJECT-level (corpus §10), shared by
  // every linked member, so deleting it on one disconnect would silence all others; and the corpus §25/§30 says the exact
  // subscription cleanup call must still be pinned from the v4 subscriber reference. The OAuth revoke above ends this
  // user's notifications. Revisit once a per-user `users/me/subscriptions` delete is pinned.

  async afterConnect(tokens, { webhookUrl }) {
    // Corpus §10: one project-level subscriber (`endpointUri`, `endpointAuthorization.secret` → sent back as
    // `Authorization: Bearer`, `subscriberConfigs`, `subscriptionCreatePolicy`). Idempotent: reuse the one already
    // pointing at our webhook. Best effort — pulls/reconcile work without it. VERIFY the resource path + body shape (§30).
    const meta: Record<string, unknown> = { legacy_user_id: tokens.raw?.legacy_user_id ?? null, subscriber_endpoint: webhookUrl }
    try {
      const project = env("GOOGLE_CLOUD_PROJECT_NUMBER"), secret = env("GOOGLE_WEBHOOK_SECRET")
      const base = `${API}/projects/${project}/subscribers`
      const list = await getJSON(base, bearer(tokens))
      const existing = ((list.subscribers as Record<string, unknown>[]) ?? []).find((s) => s.endpointUri === webhookUrl)
      if (existing) {
        meta.subscriber_id = String(existing.name ?? existing.subscriberId ?? existing.id ?? ""); meta.subscriber_status = "existing"
      } else {
        const r = await fetch(base, { method: "POST", headers: { ...bearer(tokens), "Content-Type": "application/json" }, body: JSON.stringify({ endpointUri: webhookUrl, endpointAuthorization: { secret }, subscriberConfigs: SUBSCRIBER_DATA_TYPES.map((dataType) => ({ dataType })), subscriptionCreatePolicy: "AUTOMATIC" }) })
        const text = await r.text()
        if (!r.ok) throw new VendorHttpError(r.status, `subscriber create: ${text.slice(0, 200)}`)
        const s = (text ? JSON.parse(text) : {}) as Record<string, unknown>
        meta.subscriber_id = String(s.name ?? s.subscriberId ?? s.id ?? ""); meta.subscriber_status = "created"
      }
    } catch (e) {
      meta.subscriber_status = "error"; meta.subscriber_error = String((e as Error).message ?? e).slice(0, 200)
      log("warn", "google.subscriber_failed", { fn: FN, vendor: FN, message: meta.subscriber_error })
    }
    return { meta }
  },

  /** Corpus §10 asks for 204 on acceptance; the GET/HEAD handshake and the POST probe both get 204 here. */
  challengeResponse() {
    return new Response(null, { status: 204 })
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[] | "challenge"> {
    // 1. The configured endpoint secret (corpus §11: the unauthenticated verification probe must fail 401/403).
    const expected = `Bearer ${env("GOOGLE_WEBHOOK_SECRET")}`
    if (!timingSafeEqual(req.headers.get("Authorization") ?? "", expected)) throw new Error("google subscriber secret mismatch")
    // 2. The Tink/ECDSA signature over the exact raw bytes. Fail closed whenever events are carried.
    const notifications = notificationsOf(rawBody)
    const header = req.headers.get(SIGNATURE_HEADER)
    if (header) await verifyWebhookSignature(new TextEncoder().encode(rawBody), header)
    else if (notifications.length) throw new Error("google webhook signature missing")
    // VERIFY: whether Google signs the (empty) verification probe; if it does, drop the `else` branch and always require the header.
    if (!notifications.length) return "challenge"   // the authenticated probe / an empty batch → 204 via challengeResponse
    // NOTE: the function layer answers accepted batches with 200 JSON; the corpus §10 asks for 204 — a one-line change in
    // wearable-vendor-webhook/index.ts (not this adapter's file).
    return notifications.map((n) => ({ vendorUserId: n.vendorUserId, kind: `${n.dataType}.${n.operation}`, eventId: n.eventId, windowStart: n.windowStart, windowEnd: n.windowEnd }))
  },

  async fetchRange(tokens, start, end) {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const dayF = (t: string, day: string) => `${t}.date = "${day}"`

    // Sleep (corpus §19): main sleep records ending in the window, civil day from the end instant + its offset.
    for (const p of await gget(tokens, "sleep", `sleep.interval.end_time >= "${start}T00:00:00Z" AND sleep.interval.end_time < "${addDays(end, 2)}T00:00:00Z"`, 25)) {
      const s = p.sleep as Record<string, unknown> | undefined
      const meta = (s?.metadata ?? {}) as Record<string, unknown>, iv = (s?.interval ?? {}) as Record<string, unknown>, sm = (s?.summary ?? {}) as Record<string, unknown>
      if (!s || meta.mainSleep !== true || !iv.endTime) continue
      const offset = offsetMinutes(iv.endUtcOffset as string)
      const day = dayOfISO(String(iv.endTime), offset)
      if (day < start || day > end) continue
      const { version, ...pv } = prov(p, "sleep", `sleep:${iv.endTime}`)
      const st = Object.fromEntries(((sm.stagesSummary as Record<string, unknown>[]) ?? []).map((x) => [String(x.type), x]))
      const m = (k: string) => st[k] ? (num((st[k] as Record<string, unknown>).minutes) ?? 0) * 60 : null
      const asleep = num(sm.minutesAsleep), period = num(sm.minutesInSleepPeriod)
      const extra = { ...pv, timezoneOffset: offset }
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: asleep != null ? asleep * 60 : null, [T.InBed]: period != null ? period * 60 : null, [T.REM]: m("REM"), [T.Deep]: m("DEEP"), [T.Light]: m("LIGHT"), [T.Awake]: num(sm.minutesAwake) != null ? (num(sm.minutesAwake) as number) * 60 : null,
        [T.Latency]: num(sm.minutesToFallAsleep) != null ? (num(sm.minutesToFallAsleep) as number) * 60 : null, [T.Interruptions]: st.AWAKE ? num((st.AWAKE as Record<string, unknown>).count) : null, [T.SleepEfficiency]: asleep != null && period ? 100 * asleep / period : null,
      }, { ...extra, details: { type: s.type ?? null, stages_status: meta.stagesStatus ?? null, version } }))
      dailyRows.push(...compact([dailyDate(day, T.SleepStart, String(iv.startTime), extra), dailyDate(day, T.SleepEnd, String(iv.endTime), extra)]))
      const stage: Record<string, number> = { DEEP: T.SleepDeepBinary, LIGHT: T.SleepLightBinary, REM: T.SleepREMBinary, AWAKE: T.SleepAwakeBinary, RESTLESS: T.SleepAwakeBinary, ASLEEP: T.SleepLightBinary }
      for (const g of (s.stages as Record<string, unknown>[]) ?? []) {
        const id = stage[String(g.type)]; if (!id || !g.startTime || !g.endTime) continue
        const row = epoch(String(g.startTime), id, (Date.parse(String(g.endTime)) - Date.parse(String(g.startTime))) / 60_000, { endTs: String(g.endTime), ...extra })
        if (row) epochRows.push(row)
      }
    }

    for (const day of daysBetween(start, end)) {
      for (const p of await gget(tokens, "daily-resting-heart-rate", dayF("daily_resting_heart_rate", day))) {
        const { version: _v, ...pv } = prov(p, "daily-resting-heart-rate", `daily-resting-heart-rate:${day}`)
        dailyRows.push(...dailyMap(day, { [T.HeartRateResting]: num((p.dailyRestingHeartRate as Record<string, unknown>)?.beatsPerMinute) }, pv))
      }
      // D4 / corpus §20 / 07_HRV: the daily average is documented as RMSSD → 3100 with an explicit "daily_aggregate" window.
      // It is NOT sleep HRV: 3106 is never written. The deep-sleep RMSSD field stays in details until the data type
      // itself identifies the sleep window (07_HRV: "→ 3106 when the API data type explicitly identifies the sleep window").
      for (const p of await gget(tokens, "daily-heart-rate-variability", dayF("daily_heart_rate_variability", day))) {
        const h = (p.dailyHeartRateVariability ?? {}) as Record<string, unknown>
        const { version, ...pv } = prov(p, "daily-heart-rate-variability", `daily-heart-rate-variability:${day}`)
        dailyRows.push(...dailyMap(day, { [T.Rmssd]: num(h.averageHeartRateVariabilityMilliseconds), [T.HeartRateSleep]: num(h.nonRemHeartRateBeatsPerMinute) },
          { ...pv, details: { statistic: "rmssd", window: "daily_aggregate", deep_sleep_rmssd_ms: num(h.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds), version } }))
      }
      for (const p of await gget(tokens, "daily-oxygen-saturation", dayF("daily_oxygen_saturation", day))) {
        const { version: _v, ...pv } = prov(p, "daily-oxygen-saturation", `daily-oxygen-saturation:${day}`)
        dailyRows.push(...dailyMap(day, { [T.SPO2]: num((p.dailyOxygenSaturation as Record<string, unknown>)?.averagePercentage) }, pv))
      }
      for (const p of await gget(tokens, "daily-respiratory-rate", dayF("daily_respiratory_rate", day))) {
        const { version: _v, ...pv } = prov(p, "daily-respiratory-rate", `daily-respiratory-rate:${day}`)
        dailyRows.push(...dailyMap(day, { [T.RespirationRateSleep]: num((p.dailyRespiratoryRate as Record<string, unknown>)?.breathsPerMinute) }, pv))
      }
      // 12_TEMPERATURE: nightly (°C) → 5041; nightly − baseline (both °C) → 1000106 flagged as derived; the 30-day
      // relative standard deviation is preserved in details and never labelled as a °C deviation.
      for (const p of await gget(tokens, "daily-sleep-temperature-derivations", dayF("daily_sleep_temperature_derivations", day))) {
        const t = (p.dailySleepTemperatureDerivations ?? {}) as Record<string, unknown>, n = num(t.nightlyTemperatureCelsius), b = num(t.baselineTemperatureCelsius)
        const { version, ...pv } = prov(p, "daily-sleep-temperature-derivations", `daily-sleep-temperature-derivations:${day}`)
        dailyRows.push(...dailyMap(day, { [T.SkinTemperature]: n, [T.SkinTemperatureDeviation]: n != null && b != null ? Math.round((n - b) * 1000) / 1000 : null },
          { ...pv, details: { baseline_celsius: b, relative_nightly_stddev_30d_celsius: num(t.relativeNightlyStddev30dCelsius), deviation_derived: "nightly_minus_baseline_celsius", version } }))
      }
      for (const p of await gget(tokens, "daily-vo2-max", dayF("daily_vo2_max", day))) {
        const { version: _v, ...pv } = prov(p, "daily-vo2-max", `daily-vo2-max:${day}`)
        dailyRows.push(...dailyMap(day, { [T.VO2max]: num((p.dailyVo2Max as Record<string, unknown>)?.vo2Max) }, pv))
      }
      const [st, di, ae, tc] = await Promise.all([rollup(tokens, "steps", day), rollup(tokens, "distance", day), rollup(tokens, "active-energy-burned", day), rollup(tokens, "total-calories", day)])
      const dist = num((di?.distance as Record<string, unknown>)?.millimetersSum)
      dailyRows.push(...dailyMap(day, { [T.Steps]: num((st?.steps as Record<string, unknown>)?.countSum) }, rollupProv("steps", day)))
      dailyRows.push(...dailyMap(day, { [T.CoveredDistance]: dist != null ? dist / 1000 : null }, rollupProv("distance", day)))
      dailyRows.push(...dailyMap(day, { [T.ActiveBurnedCalories]: num((ae?.activeEnergyBurned as Record<string, unknown>)?.kcalSum) }, rollupProv("active-energy-burned", day)))
      dailyRows.push(...dailyMap(day, { [T.BurnedCalories]: num((tc?.totalCalories as Record<string, unknown>)?.kcalSum) }, rollupProv("total-calories", day)))
    }

    // D4 / corpus §18: `heart-rate-variability` is RMSSD in ms → 3100 (epoch); 07_HRV: `standardDeviationMilliseconds` → 3112.
    // VERIFY: the list filter field (`sample_time.physical_time`, as for weight) and the sample envelope.
    for (const p of await gget(tokens, "heart-rate-variability", `heart_rate_variability.sample_time.physical_time >= "${start}T00:00:00Z" AND heart_rate_variability.sample_time.physical_time < "${addDays(end, 1)}T00:00:00Z"`)) {
      const h = (p.heartRateVariability ?? {}) as Record<string, unknown>, sample = (h.sampleTime ?? {}) as Record<string, unknown>
      const ts = String(sample.physicalTime ?? ""), tz = offsetMinutes(sample.utcOffset as string)
      if (!ts) continue
      const { version, ...pv } = prov(p, "heart-rate-variability", `heart-rate-variability:${ts}`)
      epochRows.push(...compact([
        epoch(ts, T.Rmssd, num(h.rootMeanSquareOfSuccessiveDifferencesMilliseconds), { ...pv, timezoneOffset: tz, details: { statistic: "rmssd", window: "sample", version } }),
        epoch(ts, T.SDNN, num(h.standardDeviationMilliseconds), { ...pv, timezoneOffset: tz, details: { statistic: "sdnn", window: "sample", version } }),
      ]))
    }

    for (const p of await gget(tokens, "weight", `weight.sample_time.physical_time >= "${start}T00:00:00Z" AND weight.sample_time.physical_time < "${addDays(end, 1)}T00:00:00Z"`)) {
      const w = (p.weight ?? {}) as Record<string, unknown>, ts = String((w.sampleTime as Record<string, unknown>)?.physicalTime ?? ""), g = num(w.weightGrams)
      if (!ts || g == null) continue
      const { version: _v, ...pv } = prov(p, "weight", `weight:${ts}`)
      const row = epoch(ts, T.Weight, g / 1000, pv)
      if (row) { epochRows.push(row); dailyRows.push(...dailyMap(ts.slice(0, 10), { [T.Weight]: g / 1000 }, pv)) }
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

/** Test hooks (the keyset cache is module state). */
export const _googleTest = { resetKeyset: () => { keysetCache = null }, ageKeyset: (ms: number) => { if (keysetCache) keysetCache.fetchedAt -= ms }, notificationsOf, cachedKeysetAt: () => keysetCache?.fetchedAt ?? null }
