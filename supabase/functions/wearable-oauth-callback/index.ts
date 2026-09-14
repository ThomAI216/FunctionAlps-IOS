// wearable-oauth-callback — PUBLIC (verify_jwt off: the vendor's browser redirect carries no JWT).
// GET ?state=…&code=… (or ?error=…) → hashes the state and consumes it atomically (single use, whatever
// happens next) → exchanges the code (PKCE verifier decrypted from the row) → vendor-specific after-connect
// (user registration / notification subscription) → stores the tokens encrypted under the account's AAD →
// mirrors `wearable_connections` → audit → queues a 30-day backfill → sends the phone back to
// functionalps://wearables/callback?vendor=…&status=ok|error[&reason=…][&target=…]. Tokens are never logged.
// Reasons the app knows: denied · expired · exchange_failed · already_linked · vendor_paused.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { APP_RETURN_URL, type AccountRow, type ExchangeResult, addDays, audit, decrypt, ensureAccount, enqueue, localDay, markAccount, serviceClient, sha256Hex, storeRaw, storeTokens, upsertConnection, vendorStatus, webhookUrl } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { errorSummary, hashId, log } from "../_shared/wearables/log.ts"

function back(vendor: string, status: "ok" | "error", reason?: string, target?: string | null): Response {
  const u = new URL(APP_RETURN_URL)
  u.searchParams.set("vendor", vendor); u.searchParams.set("status", status)
  if (reason) u.searchParams.set("reason", reason)
  if (target) u.searchParams.set("target", target)
  // A tiny page as well as the 302: some vendor sheets need a rendered response before the scheme redirect.
  return new Response(`<!doctype html><meta http-equiv="refresh" content="0;url=${u.toString()}"><p>Returning to FunctionAlps…</p>`, {
    status: 302, headers: { Location: u.toString(), "Content-Type": "text/html; charset=utf-8" },
  })
}

Deno.serve(async (req) => {
  const url = new URL(req.url)
  const state = url.searchParams.get("state")
  const code = url.searchParams.get("code")
  const oauthError = url.searchParams.get("error")
  const db = serviceClient()

  if (!state) return new Response("missing state", { status: 400 })
  const stateHex = await sha256Hex(state)
  const { data: rows, error: consumeErr } = await db.rpc("wearable_oauth_state_consume", { p_state_hex: stateHex })
  if (consumeErr) { log("error", "oauth.state_consume_failed", { fn: "wearable-oauth-callback", message: consumeErr.message }); return new Response("state error", { status: 500 }) }
  const st = (rows as { patient_id: string; vendor: string; code_verifier_enc: string | null; redirect_uri: string | null; post_auth_target: string | null; expired: boolean }[] | null)?.[0]
  if (!st) return new Response("unknown or used state", { status: 400 })
  const a = adapter(st.vendor)
  if (!a) return new Response("unknown vendor", { status: 400 })
  const target = st.post_auth_target
  if (st.expired) return back(a.key, "error", "expired", target)
  if (oauthError || !code) return back(a.key, "error", oauthError ?? "denied", target)
  if ((await vendorStatus(db, a.key)) === "paused") return back(a.key, "error", "vendor_paused", target)

  let account: AccountRow | null = null
  try {
    const codeVerifier = st.code_verifier_enc ? await decrypt(st.code_verifier_enc, { accountId: stateHex, vendor: a.key, tokenType: "verifier" }) : undefined
    let result: ExchangeResult = await a.exchangeCode({ code, redirectUri: st.redirect_uri ?? `${url.origin}${url.pathname}`, codeVerifier })
    let meta: Record<string, unknown> | undefined
    if (a.afterConnect) {
      const extra = await a.afterConnect(result, { patientId: st.patient_id, webhookUrl: webhookUrl(a.key), vendorUserId: result.vendorUserId ?? null })
      const { meta: m, ...rest } = extra
      result = { ...result, ...rest }
      meta = m
    }
    account = await ensureAccount(db, st.patient_id, a.key)
    try {
      account = await storeTokens(db, account, result, { vendorUserId: result.vendorUserId ?? null, meta: meta ?? account.meta ?? null, status: "connected", grantedScopes: result.scopes ?? null })
    } catch (e) {
      // The partial unique index (vendor, vendor_user_id) among live accounts: this vendor user is linked elsewhere.
      if (/23505|duplicate key|wearable_vendor_accounts_live_vendor_user/.test(String((e as Error).message))) {
        await markAccount(db, account.id, { status: "error", last_error_code: "already_linked" })
        await audit(db, { patientId: st.patient_id, vendor: a.key, accountId: account.id, action: "connect_refused", actor: "member", details: { code: "already_linked" } })
        return back(a.key, "error", "already_linked", target)
      }
      throw e
    }
    await upsertConnection(db, st.patient_id, a.key, true)
    const rawId = await storeRaw(db, st.patient_id, a.key, "oauth_callback", { vendor: a.key, vendorUserId: result.vendorUserId ?? null, scopes: result.scopes ?? null, meta: meta ?? null }, { vendorUserId: result.vendorUserId ?? null })
    await audit(db, { patientId: st.patient_id, vendor: a.key, accountId: account.id, action: "connect", actor: "member", details: { scopes: result.scopes ?? null } })
    await db.from("wearable_sync_state").upsert({ account_id: account.id, patient_id: st.patient_id, vendor: a.key, last_backfill_at: new Date().toISOString(), updated_at: new Date().toISOString() }, { onConflict: "account_id" })
    const today = localDay(new Date())
    await enqueue(db, { patientId: st.patient_id, vendor: a.key, vendorUserId: result.vendorUserId ?? st.patient_id, kind: "backfill", syncKind: "backfill", windowStart: addDays(today, -30), windowEnd: today, rawEventId: rawId, priority: 5, accountId: account.id, dedupeKey: `backfill:${account.id}` })
    log("info", "oauth.connected", { fn: "wearable-oauth-callback", vendor: a.key, account: account.id, patientHash: await hashId(st.patient_id) })
    return back(a.key, "ok", undefined, target)
  } catch (e) {
    log("error", "oauth.callback_failed", { fn: "wearable-oauth-callback", vendor: a.key, ...errorSummary(e) })
    if (account) await markAccount(db, account.id, { status: account.access_token_enc ? account.status : "error", last_error_code: "exchange_failed" })
    return back(a.key, "error", "exchange_failed", target)
  }
})
