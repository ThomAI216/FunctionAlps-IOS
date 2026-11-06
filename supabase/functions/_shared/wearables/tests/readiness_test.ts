// The `vendor-readiness` ops probe (2026-11-06): it must describe each vendor's authorisation URL and secrets
// WITHOUT ever returning a value — names → booleans, URL → origin, path and parameter names.
import { assert, assertEquals } from "jsr:@std/assert@1"
import { adapters } from "../registry.ts"
import { authorizeCheck, secretPresence, VENDOR_EXTRA_SECRETS } from "../readiness.ts"

const REDIRECT = "https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback"

Deno.test("authorizeCheck: WHOOP builds without PKCE; Garmin builds WITH the S256 challenge; no value leaks", () => {
  const w = authorizeCheck(adapters.whoop, "whoop-client-id-123", REDIRECT)
  assertEquals([w.ok, w.origin, w.redirectExact, w.pkce], [true, "https://api.prod.whoop.com", true, false])
  assert(w.params!.includes("client_id") && w.params!.includes("state"))
  assert(!JSON.stringify(w).includes("whoop-client-id-123"))
  const g = authorizeCheck(adapters.garmin, "garmin-client-id-456", REDIRECT)
  assertEquals([g.ok, g.origin, g.path, g.pkce], [true, "https://connect.garmin.com", "/oauth2Confirm", true])
  assert(!JSON.stringify(g).includes("garmin-client-id-456"))
})

Deno.test("authorizeCheck: an unset client id is reported, not thrown", () => {
  assertEquals(authorizeCheck(adapters.oura, undefined, REDIRECT), { ok: false, error: "OURA_CLIENT_ID unset" })
})

Deno.test("secretPresence: names → booleans only; the optional marker is kept, the value never returned", () => {
  Deno.env.set("READINESS_TEST_SECRET", "s3cr3t-value")
  const p = secretPresence(["READINESS_TEST_SECRET", "READINESS_TEST_ABSENT?"])
  assertEquals(p, { READINESS_TEST_SECRET: true, "READINESS_TEST_ABSENT?": false })
  assert(!JSON.stringify(p).includes("s3cr3t"))
  Deno.env.delete("READINESS_TEST_SECRET")
})

Deno.test("every registered vendor has an extra-secrets entry (the probe covers the whole registry)", () => {
  assertEquals(Object.keys(VENDOR_EXTRA_SECRETS).sort(), Object.keys(adapters).sort())
  assertEquals(VENDOR_EXTRA_SECRETS.garmin, ["GARMIN_WEBHOOK_TOKEN", "GARMIN_PULL_ENABLED?"])
})
