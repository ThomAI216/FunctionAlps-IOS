// The seven direct vendors (owner decision 2026-09-04). A vendor is offered to members only when its
// `wearable_vendors.status` is `available` — flipped by the owner once the developer app is approved —
// so a new vendor needs no app release.
import type { VendorAdapter, VendorKey } from "./core.ts"
import { oura } from "./oura.ts"
import { whoop } from "./whoop.ts"
import { polar } from "./polar.ts"
import { garmin } from "./garmin.ts"
import { withings } from "./withings.ts"
import { suunto } from "./suunto.ts"
import { google } from "./google.ts"

export const adapters: Record<VendorKey, VendorAdapter> = { oura, whoop, polar, garmin, withings, suunto, google }

export function adapter(key: string | null | undefined): VendorAdapter | null {
  if (!key) return null
  return (adapters as Record<string, VendorAdapter>)[key] ?? null
}
