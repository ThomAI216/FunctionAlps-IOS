// wearable-ingest — authenticated MEMBER endpoint for DEVICE-submitted samples.
//
// The native iOS app reads Apple Health locally (HealthKitReader) and POSTs a batch of
// already-normalised rows here: the raw submission is stored verbatim (own the bytes), then the
// rows are upserted on their natural keys (an idempotent re-sync is safe). RLS member policies on
// the wearable tables are SELECT-only, so the phone cannot write directly — this function verifies
// the caller (resolvePatientId) and writes with the service-role client, like thryve-webhook.
//
// Body: { daily?: DailyIn[], epoch?: EpochIn[], connection?: "connected" | "disconnected" }
//   • daily/epoch — data_source_id defaults to the Apple Health sentinel 1000001; data_type_id
//     is the CM OS wearable CATALOGUE id (Steps 1000, …, SDNN 3112) so `wearable_daily_labeled`
//     labels the rows; workouts travel as id 0 + data_type_name "workout" epochs.
//   • connection — records "Apple Health on this phone" in `wearable_connections` (upsert on
//     patient_id + data_source_id, the same row shape thryve-webhook writes). A body with only
//     `connection` is valid: connecting a phone with no health data yet is still a connection.
//
// Source of truth for this function: FunctionAlps-IOS/supabase/functions/wearable-ingest/index.ts
// (single file — the two helpers are inlined so the MCP deploy needs no relative imports).
// Deploy: Supabase MCP `deploy_edge_function` (verify_jwt = true).
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

const APPLE_HEALTH_SOURCE_ID = 1000001
const APPLE_HEALTH_SOURCE_NAME = "apple_health"

type DailyIn = {
  day: string
  data_type_name: string
  value?: number | null
  value_text?: string | null
  value_type?: string | null
  timezone_offset?: number | null
  details?: Record<string, unknown> | null
  recorded_at?: string | null
  data_source_id?: number
  data_type_id?: number
}
type EpochIn = {
  start_ts: string
  end_ts?: string | null
  data_type_name: string
  value?: number | null
  value_text?: string | null
  value_type?: string | null
  timezone_offset?: number | null
  details?: Record<string, unknown> | null
  data_source_id?: number
  data_type_id?: number
}
type ConnectionIn = "connected" | "disconnected"

function num(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN
  return Number.isFinite(n) ? n : null
}

function createServiceRoleClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
}

/** The caller's patient id from the bearer JWT, or null. */
async function resolvePatientId(req: Request, db: SupabaseClient): Promise<string | null> {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader?.startsWith("Bearer ")) return null
  const token = authHeader.slice("Bearer ".length)
  const { data: { user }, error: authError } = await db.auth.getUser(token)
  if (authError || !user) return null
  const { data, error } = await db.from("patients").select("id").eq("auth_user_id", user.id).maybeSingle()
  if (error) return null
  return data?.id ?? null
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  const db = createServiceRoleClient()
  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)

  let body: { daily?: DailyIn[]; epoch?: EpochIn[]; connection?: ConnectionIn }
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }

  const dailyIn = Array.isArray(body.daily) ? body.daily : []
  const epochIn = Array.isArray(body.epoch) ? body.epoch : []
  const connection: ConnectionIn | null =
    body.connection === "connected" || body.connection === "disconnected" ? body.connection : null
  if (!dailyIn.length && !epochIn.length && !connection) {
    return json({ error: "Nothing to ingest: provide daily[] and/or epoch[] (or connection)" }, 400)
  }

  try {
    let rawEventId: string | null = null
    let dailyCount = 0
    let epochCount = 0

    if (dailyIn.length || epochIn.length) {
      // 1) The raw submission, verbatim.
      const { data: rawRow, error: rawErr } = await db
        .from("wearable_raw_events")
        .insert({
          patient_id: patientId,
          provider: "apple_health",
          kind: "native_healthkit",
          payload: { daily: dailyIn, epoch: epochIn } as unknown as Record<string, unknown>,
        })
        .select("id")
        .single()
      if (rawErr) throw new Error(`raw insert: ${rawErr.message}`)
      rawEventId = rawRow?.id ?? null

      // 2) Normalise → upsert. Malformed rows are skipped, not fatal.
      const dailyRows = dailyIn
        .filter((d) => d?.day && d?.data_type_name)
        .map((d) => ({
          patient_id: patientId,
          data_source_id: d.data_source_id ?? APPLE_HEALTH_SOURCE_ID,
          day: d.day,
          data_type_id: d.data_type_id ?? 0,
          data_type_name: d.data_type_name,
          value: num(d.value),
          value_text: d.value_text ?? null,
          value_type: d.value_type ?? null,
          timezone_offset: d.timezone_offset ?? null,
          details: d.details ?? null,
          raw_event_id: rawEventId,
          recorded_at: d.recorded_at ?? null,
        }))

      const epochRows = epochIn
        .filter((e) => e?.start_ts && e?.data_type_name)
        .map((e) => ({
          patient_id: patientId,
          data_source_id: e.data_source_id ?? APPLE_HEALTH_SOURCE_ID,
          data_type_id: e.data_type_id ?? 0,
          data_type_name: e.data_type_name,
          value: num(e.value),
          value_text: e.value_text ?? null,
          value_type: e.value_type ?? null,
          start_ts: e.start_ts,
          end_ts: e.end_ts ?? null,
          timezone_offset: e.timezone_offset ?? null,
          details: e.details ?? null,
          raw_event_id: rawEventId,
        }))

      if (epochRows.length) {
        const { error: e } = await db
          .from("wearable_epoch")
          .upsert(epochRows, { onConflict: "patient_id,data_source_id,data_type_id,start_ts" })
        if (e) throw new Error(`epoch upsert: ${e.message}`)
      }
      if (dailyRows.length) {
        const { error: e } = await db
          .from("wearable_daily")
          .upsert(dailyRows, { onConflict: "patient_id,data_source_id,day,data_type_id" })
        if (e) throw new Error(`daily upsert: ${e.message}`)
      }
      dailyCount = dailyRows.length
      epochCount = epochRows.length
    }

    // 3) The connection itself (explicit state from the phone, or implied by accepted rows).
    const state: ConnectionIn | null = connection ?? (dailyCount + epochCount > 0 ? "connected" : null)
    if (state) {
      const now = new Date().toISOString()
      const row: Record<string, unknown> = {
        patient_id: patientId,
        data_source_id: APPLE_HEALTH_SOURCE_ID,
        data_source_name: APPLE_HEALTH_SOURCE_NAME,
        status: state,
        updated_at: now,
      }
      if (state === "connected") row.connected_at = now
      else row.disconnected_at = now
      const { error: e } = await db.from("wearable_connections").upsert(row, { onConflict: "patient_id,data_source_id" })
      if (e) throw new Error(`connection upsert: ${e.message}`)
    }

    return json({ ok: true, raw_event_id: rawEventId, daily: dailyCount, epoch: epochCount, connection: state })
  } catch (e) {
    console.error("[wearable-ingest]", String(e))
    return json({ error: "Could not ingest wearable data" }, 500)
  }
})
