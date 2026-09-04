// wearable-oauth-callback — PUBLIC (verify_jwt off: the vendor's browser redirect carries no JWT).
// GET ?state=…&code=… (or ?error=…) → validates the single-use state → exchanges the code →
// vendor-specific after-connect (user registration / notification subscription) → stores the tokens
// encrypted → mirrors `wearable_connections` → queues a 30-day backfill → sends the phone back to
// functionalps://wearables/callback?vendor=…&status=ok|error[&reason=…]. Tokens are never logged.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { APP_RETURN_URL, enqueue, addDays, localDay, oauthRedirectUri, serviceClient, storeRaw, storeTokens, upsertConnection, webhookUrl } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"

function back(vendor: string, status: "ok" | "error", reason?: string): Response {
  const u = new URL(APP_RETURN_URL)
  u.searchParams.set("vendor", vendor); u.searchParams.set("status", status)
  if (reason) u.searchParams.set("reason", reason)
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
  const { data: st } = await db.from("wearable_oauth_states").select("state,patient_id,vendor,code_verifier,expires_at").eq("state", state).maybeSingle()
  await db.from("wearable_oauth_states").delete().eq("state", state)  // single use, whatever happens next
  if (!st) return new Response("unknown or used state", { status: 400 })
  const a = adapter(st.vendor)
  if (!a) return new Response("unknown vendor", { status: 400 })
  if (new Date(st.expires_at).getTime() < Date.now()) return back(a.key, "error", "expired")
  if (oauthError || !code) return back(a.key, "error", oauthError ?? "denied")

  try {
    let tokens = await a.exchangeCode({ code, redirectUri: oauthRedirectUri(), codeVerifier: st.code_verifier ?? undefined })
    let meta: Record<string, unknown> | undefined
    if (a.afterConnect) {
      const extra = await a.afterConnect(tokens, { patientId: st.patient_id, webhookUrl: webhookUrl(a.key) })
      const { meta: m, ...rest } = extra
      tokens = { ...tokens, ...rest }
      meta = m
    }
    await storeTokens(db, st.patient_id, a.key, tokens, meta)
    await upsertConnection(db, st.patient_id, a.key, true)
    const rawId = await storeRaw(db, st.patient_id, a.key, "oauth_callback", { vendor: a.key, vendorUserId: tokens.vendorUserId ?? null, scopes: tokens.scopes ?? null, meta: meta ?? null }, tokens.vendorUserId)
    const today = localDay(new Date())
    await enqueue(db, st.patient_id, a.key, tokens.vendorUserId ?? st.patient_id, "backfill", addDays(today, -30), today, rawId)
    return back(a.key, "ok")
  } catch (e) {
    console.error("[wearable-oauth-callback]", a.key, String(e).slice(0, 300))
    return back(a.key, "error", "exchange_failed")
  }
})
