// D6 (2026-09-14): Garmin is a portal stub. Every method must throw `GarminPortalError`
// (`code === "portal_not_approved"`) and none of them may reach the network.
import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1"
import type { AccountContext, TokenSet } from "../core.ts"
import { GarminPortalError, garmin } from "../garmin.ts"

const tokens: TokenSet = { accessToken: "a", refreshToken: "r", expiresAt: 0 }
const ctx: AccountContext = { patientId: "p", vendorUserId: "u", meta: {} }

/** Runs `fn` with `globalThis.fetch` replaced by one that fails the test. */
async function withNoNetwork(fn: () => Promise<void> | void): Promise<void> {
  const real = globalThis.fetch
  globalThis.fetch = (input: string | URL | Request) => { throw new Error(`network call attempted: ${String(input).slice(0, 120)}`) }
  try { await fn() } finally { globalThis.fetch = real }
}

const isPortalError = (e: unknown) => {
  assert(e instanceof GarminPortalError, `expected GarminPortalError, got ${String(e)}`)
  assertEquals(e.code, "portal_not_approved"); assertEquals(e.message, "portal_not_approved"); assertEquals(e.name, "GarminPortalError")
}

Deno.test("garmin: the registry key and the stub's static contract", () => {
  assertEquals(garmin.key, "garmin"); assertEquals(garmin.name, "Garmin")
  assertEquals(garmin.pkce, "not_documented"); assertEquals(garmin.scopes, [])
  assertEquals(garmin.reconcile, { nightlyDays: 3, weeklyDays: 14 })
})

Deno.test("garmin: authorizeURL throws portal_not_approved (authorization endpoint is portal-gated)", () =>
  withNoNetwork(() => {
    const e = assertThrows(() => garmin.authorizeURL({ clientId: "c", redirectUri: "https://x/cb", state: "s", codeChallenge: "ch" }))
    isPortalError(e)
  }))

Deno.test("garmin: exchangeCode rejects with portal_not_approved", () =>
  withNoNetwork(async () => isPortalError(await assertRejects(() => garmin.exchangeCode({ code: "c", redirectUri: "https://x/cb", codeVerifier: "v" })))))

Deno.test("garmin: refresh rejects with portal_not_approved", () =>
  withNoNetwork(async () => isPortalError(await assertRejects(() => garmin.refresh("r")))))

Deno.test("garmin: revoke rejects with portal_not_approved", () =>
  withNoNetwork(async () => { assert(garmin.revoke); isPortalError(await assertRejects(() => garmin.revoke!(tokens, ctx))) }))

Deno.test("garmin: afterConnect rejects with portal_not_approved", () =>
  withNoNetwork(async () => { assert(garmin.afterConnect); isPortalError(await assertRejects(() => garmin.afterConnect!(tokens, { patientId: "p", webhookUrl: "https://x/wh", vendorUserId: "u" }))) }))

Deno.test("garmin: fetchRange rejects with portal_not_approved", () =>
  withNoNetwork(async () => isPortalError(await assertRejects(() => garmin.fetchRange(tokens, "2026-09-01", "2026-09-03", ctx)))))

Deno.test("garmin: parseWebhook throws portal_not_approved even with a matching garmin-client-id header (no header-based verification)", () =>
  withNoNetwork(() => {
    const req = new Request("https://x/wearable-vendor-webhook/garmin", { method: "POST", headers: { "garmin-client-id": "c", "content-type": "application/json" } })
    const e = assertThrows(() => garmin.parseWebhook(req, JSON.stringify({ dailies: [{ userId: "u", steps: 1 }] }), new URL(req.url)))
    isPortalError(e)
  }))

Deno.test("garmin: no method exposes a challenge/unsubscribe path that could answer a vendor without a contract", () => {
  assertEquals(garmin.challengeResponse, undefined); assertEquals(garmin.unsubscribe, undefined)
})
