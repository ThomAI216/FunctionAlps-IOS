// Garmin Health API: reviewed business applicants; FunctionAlps has no approved contract yet — adapter stubbed 2026-09-14, D6.
//
// Status (corpus `vendors/garmin.md`, pack `23_VENDOR_STATUS_AND_OWNER_STEPS.md`): the 2026 Connect Developer
// Program pages invite reviewed business applicants (the earlier "program closed" claim was wrong). Every
// implementation-critical detail — OAuth authorize/token/refresh/revoke endpoints, PKCE mode, scopes, user
// identity, feed schemas, webhook authentication, rate limits, backfill horizon — is PORTAL-GATED and is
// handed over only after approval. The corpus forbids coding from mirror docs, so this adapter:
//   • throws `GarminPortalError` (`code = "portal_not_approved"`) from every method that would touch the
//     network — including `authorizeURL` (the authorization endpoint is not documented publicly) and
//     `parseWebhook` (the webhook function answers 401; there is NO client-id-header "verification": that
//     header is not a secret and is not a signature — `20_WEBHOOK_SYNC_SECURITY.md`);
//   • keeps `key`/`name`/`pkce`/`scopes`/`reconcile` so the registry, the status gate
//     (`wearable_vendors.status` stays `planned`) and the AI policy (`ai-policy.ts`: deny) keep working.
// The previous live adapter (endpoints + `mapItem` catalogue mapping, all unverified) is preserved for
// reference at `_retired/wearables-garmin-v1-2026-09-04.ts`, with the re-instatement conditions in its header.
import type { VendorAdapter } from "./core.ts"

/** Thrown by every Garmin method: the vendor is not usable until the approved-partner docs are imported. */
export class GarminPortalError extends Error {
  code = "portal_not_approved" as const
  constructor() { super("portal_not_approved"); this.name = "GarminPortalError" }
}

const blocked = (): never => { throw new GarminPortalError() }

export const garmin: VendorAdapter = {
  key: "garmin",
  name: "Garmin",
  pkce: "not_documented",   // corpus §5–7: OAuth 2.0 is stated, the PKCE mode is portal-gated
  scopes: [],               // corpus §6/§12: scopes and data grants are portal-gated
  reconcile: { nightlyDays: 3, weeklyDays: 14 },

  authorizeURL: blocked,    // corpus §6: authorization endpoint PORTAL-GATED → no URL can be built
  exchangeCode: () => Promise.reject(new GarminPortalError()),
  refresh: () => Promise.reject(new GarminPortalError()),
  revoke: () => Promise.reject(new GarminPortalError()),
  afterConnect: () => Promise.reject(new GarminPortalError()),
  parseWebhook: blocked,    // corpus §11: `verifyGarminWebhook()` must throw `portal_not_approved`
  fetchRange: () => Promise.reject(new GarminPortalError()),
}
