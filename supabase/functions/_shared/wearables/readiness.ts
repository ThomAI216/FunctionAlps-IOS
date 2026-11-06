// Ops probe `{"probe":"vendor-readiness"}` on `wearable-reconcile` (x-report-secret) — added 2026-11-06.
// Answers, per vendor, what an operator needs before and after flipping `wearable_vendors.status`:
//   • which Edge Function secrets are SET (names → true/false; never a value, never a length),
//   • whether the adapter can build its OAuth authorisation URL with the secrets as they are (origin + path + the
//     query parameter NAMES, and whether the redirect URI is exactly our callback),
//   • the status row, the live accounts and the last successful sync (counts and timestamps only).
// It calls no vendor and writes nothing. Pure parts are exported for the tests.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import { type VendorAdapter, type VendorKey, LIVE_STATUSES, oauthRedirectUri, sendsPKCE } from "./core.ts"
import { adapters } from "./registry.ts"

/** Secrets each vendor needs beyond `<VENDOR>_CLIENT_ID` / `_CLIENT_SECRET`; `?` marks an optional one. */
export const VENDOR_EXTRA_SECRETS: Record<VendorKey, string[]> = {
  oura: ["OURA_WEBHOOK_VERIFICATION_TOKEN", "OURA_MAINTAIN_SUBSCRIPTIONS?"],
  whoop: [],
  polar: ["POLAR_WEBHOOKS_ENABLED?", "POLAR_WEBHOOK_SECRET?"],
  garmin: [],
  withings: ["WITHINGS_REGION?"],
  suunto: ["SUUNTO_SUBSCRIPTION_KEY", "SUUNTO_WEBHOOK_SECRET"],
  google: ["GOOGLE_WEBHOOK_SECRET", "GOOGLE_CLOUD_PROJECT_NUMBER?"],
  strava: ["STRAVA_WEBHOOK_VERIFY_TOKEN", "STRAVA_SUBSCRIPTION_ID?"],
}

export const PLATFORM_SECRETS = ["WEARABLE_TOKEN_KEY", "REPORT_SECRET", "WEARABLE_LOG_SALT?"]

const isSet = (name: string) => { const v = Deno.env.get(name); return v != null && v !== "" }

export function secretPresence(names: string[]): Record<string, boolean> {
  return Object.fromEntries(names.map((n) => [n, isSet(n.replace(/\?$/, ""))]))
}

export interface AuthorizeCheck { ok: boolean; origin?: string; path?: string; params?: string[]; redirectExact?: boolean; pkce?: boolean; error?: string }

/** Builds the authorisation URL the way `wearable-oauth-start` does, and describes it without its values. */
export function authorizeCheck(a: VendorAdapter, clientId: string | undefined, redirectUri: string): AuthorizeCheck {
  if (!clientId) return { ok: false, error: `${a.key.toUpperCase()}_CLIENT_ID unset` }
  try {
    const u = new URL(a.authorizeURL({ clientId, redirectUri, state: "readiness-probe", codeChallenge: sendsPKCE(a.pkce) ? "readiness-probe-challenge" : undefined }))
    return {
      ok: u.protocol === "https:" && u.searchParams.get("client_id") === clientId && u.searchParams.get("redirect_uri") === redirectUri,
      origin: u.origin, path: u.pathname, params: [...new Set(u.searchParams.keys())].sort(),
      redirectExact: u.searchParams.get("redirect_uri") === redirectUri, pkce: u.searchParams.has("code_challenge"),
    }
  } catch (e) {
    return { ok: false, error: (e as Error)?.name === "GarminPortalError" ? "portal_not_approved" : String((e as Error)?.message ?? e).slice(0, 120) }
  }
}

export async function vendorReadiness(db: SupabaseClient) {
  const redirectUri = oauthRedirectUri()
  const { data: rows } = await db.from("wearable_vendors").select("key, status, data_source_id")
  const { data: accounts } = await db.from("wearable_vendor_accounts").select("vendor, status, last_successful_sync_at")
  const out: Record<string, unknown> = {}
  for (const a of Object.values(adapters)) {
    const up = a.key.toUpperCase()
    const row = (rows ?? []).find((r: { key: string }) => r.key === a.key) as { status: string; data_source_id: number } | undefined
    const mine = ((accounts ?? []) as { vendor: string; status: string; last_successful_sync_at: string | null }[]).filter((r) => r.vendor === a.key)
    const lastOk = mine.map((r) => r.last_successful_sync_at).filter((x): x is string => !!x).sort().pop() ?? null
    out[a.key] = {
      status: row?.status ?? "no_row", dataSourceId: row?.data_source_id ?? null,
      secrets: secretPresence([`${up}_CLIENT_ID`, `${up}_CLIENT_SECRET`, ...VENDOR_EXTRA_SECRETS[a.key]]),
      authorize: authorizeCheck(a, Deno.env.get(`${up}_CLIENT_ID`) ?? undefined, redirectUri),
      accounts: { total: mine.length, live: mine.filter((r) => LIVE_STATUSES.includes(r.status as never)).length },
      lastSuccessfulSyncAt: lastOk,
    }
  }
  return { redirectUri, platform: secretPresence(PLATFORM_SECRETS), vendors: out }
}
