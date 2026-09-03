// member-scores — the FunctionAlps scoring engine, SERVER-SIDE (PRD §41).
//
// The engine under ./engine is the Expo app's `lib/health/*` (+ nutrition snapshot,
// nutrient data, health details, marker trends, TDEE) copied VERBATIM with only the
// import paths rewritten and the React/i18n tails removed — so a score computed here
// equals the one the web app computes on the device, by construction. Change the
// engine in the Expo repo first, then re-copy (FunctionAlps-IOS/supabase/README.md).
//
// Inputs are read under the CALLER's JWT (own-rows RLS); nothing is written.
// The body carries the member's UTC offset so day boundaries match their device.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createUserScopedClient } from "../_shared/supabase.ts"
import { deriveTrends, type TrendsProfile } from "./engine/health/trends-derive.ts"
import { parseTodayCheckin } from "./engine/checkin/load-today.ts"
import { engineNow, localDayISO, setClockOffsetMinutes, shiftToWallClock } from "./engine/dates/local-day.ts"
import type { MealLog, AnalyzedItem, MealMicros } from "./engine/types/log-store.ts"
import type { CheckinHistoryEntry } from "./engine/types/daily-store.ts"
import type { GutHistoryEntry } from "./engine/checkin/marker-trends.ts"
import { overallTrend } from "./engine/health/overall-trend.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

const TREND_DAYS = 13 // 13 past days + today = the 14-day window (Trends tab)
const MEAL_DAYS = 30 // the Food store's window (loadMeals)

const num = (v: unknown): number | null => (typeof v === "number" ? v : v != null && !Number.isNaN(Number(v)) ? Number(v) : null)
const und = (v: number | null): number | undefined => (v === null ? undefined : v)

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "POST only" }, 405)

  let body: { tzOffsetMinutes?: number } = {}
  try { body = await req.json() } catch { /* empty body is fine */ }
  const offset = Number.isFinite(body.tzOffsetMinutes) ? Math.max(-840, Math.min(840, Number(body.tzOffsetMinutes))) : 0
  setClockOffsetMinutes(offset)

  const db = createUserScopedClient(req)

  // patient id = public.patients.id, never auth.uid() — the same ladder every app uses.
  const { data: patientId, error: pidErr } = await db.rpc("current_member_patient_id")
  if (pidErr) return json({ error: pidErr.message }, 401)
  if (!patientId) return json({ error: "No patient profile for this account" }, 404)

  const now = engineNow()
  const today = localDayISO(now)
  const dayCutoff = (back: number) => { const d = new Date(now); d.setDate(d.getDate() - back); return localDayISO(d) }
  const sinceMeals = new Date(Date.now() - MEAL_DAYS * 86_400_000).toISOString()

  const [mealsRes, reactionsRes, fnRes, gutRes, todayRes, profileRes] = await Promise.all([
    db.from("nb_meal_logs")
      .select("id, name, meal_type, logged_at, total_calories, total_protein_g, total_carbs_g, total_fat_g, total_fiber_g, micronutrient_totals, inflammation_score, glycemic_score, gut_score, ai_identified_foods")
      .eq("patient_id", patientId).gte("logged_at", sinceMeals).order("logged_at", { ascending: true }).limit(100),
    db.from("nb_meal_reactions")
      .select("meal_log_id, overall, bloating, gas_burden, fullness, reaction_flags")
      .eq("patient_id", patientId).gte("reaction_time", sinceMeals),
    db.from("patient_daily_checkins")
      .select("checkin_date, mood, digestion, energy, sleep, sleep_quality, stress, inflammation, energy_overall, sleep_overall, mood_score, stress_score, recovery, soreness, recent_load, recent_mental_load")
      .eq("patient_id", patientId).not("functional_completed_at", "is", null).lt("checkin_date", today).gte("checkin_date", dayCutoff(TREND_DAYS))
      .order("checkin_date", { ascending: true }).limit(TREND_DAYS + 1),
    db.from("patient_daily_checkins")
      .select("checkin_date, bloating, burns, gas_burden, stool_quality, stool_frequency, gut_comfort, gut_overall, gut_stool")
      .eq("patient_id", patientId).not("intelligence_completed_at", "is", null).lt("checkin_date", today).gte("checkin_date", dayCutoff(TREND_DAYS))
      .order("checkin_date", { ascending: true }).limit(TREND_DAYS + 1),
    db.from("patient_daily_checkins")
      .select("checkin_date, functional_completed_at, intelligence_completed_at, mood, digestion, energy, sleep, sleep_quality, stress, inflammation, bloating, burns, gas_burden, stool_quality, stool_frequency, energy_overall, sleep_overall, mood_score, stress_score, gut_comfort, gut_overall, gut_stool, functional_detail, gut_detail, recovery, soreness, recent_load, recent_mental_load")
      .eq("patient_id", patientId).eq("checkin_date", today).maybeSingle(),
    db.from("nb_patient_app_profiles")
      .select("app_sex, app_weight_kg, app_height_cm, app_age, activity_level, goal_mode, estimated_body_fat_percent, macros_customized, target_calories, target_protein_g, target_carbs_g, target_fat_g, custom_calorie_offset_kcal")
      .eq("patient_id", patientId).maybeSingle(),
  ])
  for (const r of [mealsRes, reactionsRes, fnRes, gutRes, todayRes, profileRes]) {
    if (r.error) return json({ error: r.error.message }, 500)
  }

  // ── meals, exactly as lib/stores/log-store.ts#loadMeals shapes them ──────────
  const reactions = new Map<string, { overall?: number; flags?: string[]; bloating?: number; gasBurden?: number; fullness?: number }>()
  for (const rr of (reactionsRes.data ?? []) as Record<string, unknown>[]) {
    reactions.set(String(rr.meal_log_id), {
      overall: und(num(rr.overall)), flags: Array.isArray(rr.reaction_flags) ? (rr.reaction_flags as string[]) : undefined,
      bloating: und(num(rr.bloating)), gasBurden: und(num(rr.gas_burden)), fullness: und(num(rr.fullness)),
    })
  }
  const meals: MealLog[] = ((mealsRes.data ?? []) as Record<string, unknown>[]).map((r) => {
    const items = Array.isArray(r.ai_identified_foods) ? (r.ai_identified_foods as AnalyzedItem[]) : undefined
    const itemSum = (k: "kcal" | "protein_g" | "carbs_g" | "fat_g"): number | undefined =>
      items && items.length ? Math.round(items.reduce((a, it) => a + (typeof it[k] === "number" ? (it[k] as number) : 0), 0)) : undefined
    const hasScores = r.inflammation_score != null || r.glycemic_score != null || r.gut_score != null
    const reaction = reactions.get(String(r.id))
    return {
      id: String(r.id),
      dbId: String(r.id),
      name: (r.name as string) ?? "Meal",
      mealType: ((r.meal_type as MealLog["mealType"]) ?? "snack"),
      estimatedCalories: itemSum("kcal") ?? und(num(r.total_calories)),
      estimatedProtein: itemSum("protein_g") ?? und(num(r.total_protein_g)),
      estimatedCarbs: itemSum("carbs_g") ?? und(num(r.total_carbs_g)),
      estimatedFat: itemSum("fat_g") ?? und(num(r.total_fat_g)),
      // Shifted into the member's wall clock so day bucketing matches their device.
      timestamp: shiftToWallClock(String(r.logged_at)),
      micros: { ...(((r.micronutrient_totals as MealMicros | null) ?? {}) as MealMicros), fiber_g: und(num(r.total_fiber_g)) },
      scores: hasScores
        ? { inflammation: Number(r.inflammation_score ?? 0), glycemic: Number(r.glycemic_score ?? 0), digestion: Number(r.gut_score ?? 0) }
        : undefined,
      reactionOverall: reaction?.overall, reactionFlags: reaction?.flags,
      reactionBloating: reaction?.bloating, reactionGasBurden: reaction?.gasBurden, reactionFullness: reaction?.fullness,
      items,
    }
  })

  // ── histories, exactly as lib/checkin/persistence.ts shapes them ─────────────
  const metricHistory: CheckinHistoryEntry[] = ((fnRes.data ?? []) as Record<string, unknown>[]).map((row) => ({
    date: row.checkin_date as string,
    mood: num(row.mood), digestion: num(row.digestion), energy: num(row.energy), sleep: num(row.sleep),
    sleepQuality: num(row.sleep_quality), stress: num(row.stress), inflammation: num(row.inflammation),
    energyOverall: num(row.energy_overall), sleepOverall: num(row.sleep_overall), moodScore: num(row.mood_score), stressScore: num(row.stress_score),
    recovery: num(row.recovery), soreness: num(row.soreness), recentLoad: num(row.recent_load), recentMentalLoad: num(row.recent_mental_load),
  }))
  const gutHistory: GutHistoryEntry[] = ((gutRes.data ?? []) as Record<string, unknown>[]).map((row) => ({
    date: row.checkin_date as string,
    bloating: num(row.bloating), burns: num(row.burns), gasBurden: num(row.gas_burden),
    stoolQuality: num(row.stool_quality), stoolFrequency: num(row.stool_frequency),
    comfort: num(row.gut_comfort), gutOverall: num(row.gut_overall), stool: num(row.gut_stool),
  }))
  const todayCheckin = parseTodayCheckin((todayRes.data as Record<string, unknown> | null) ?? null, true)

  // ── profile (the onboarding store's fields, from the DB row) ─────────────────
  const p = (profileRes.data ?? {}) as Record<string, unknown>
  const customised = p.macros_customized === true
  const profile: TrendsProfile = {
    sex: p.app_sex === "male" || p.app_sex === "female" ? p.app_sex : null,
    weight: p.app_weight_kg != null ? String(p.app_weight_kg) : "",
    height: p.app_height_cm != null ? String(p.app_height_cm) : "",
    age: p.app_age != null ? String(p.app_age) : "",
    activityLevel: (p.activity_level as string | null) ?? null,
    goalMode: p.goal_mode === "build" || p.goal_mode === "cut" || p.goal_mode === "maintain" ? p.goal_mode : null,
    estimatedBfPercent: num(p.estimated_body_fat_percent),
    customMacros: customised
      ? { proteinG: und(num(p.target_protein_g)), carbsG: und(num(p.target_carbs_g)), fatG: und(num(p.target_fat_g)), calories: und(num(p.target_calories)) }
      : null,
    customCalorieOffset: num(p.custom_calorie_offset_kcal),
  }

  const result = deriveTrends({
    meals,
    metricHistory,
    gutHistory,
    today: todayCheckin,
    checkin: null,
    gutCompletedToday: !!todayCheckin?.intelligenceDoneAt,
    profile,
    now,
  })

  // The crown's direction, from the same composite series the headline number ends.
  const crownSeries = result.compositeSeries14d.filter((v): v is number => v != null)
  const trend = overallTrend(crownSeries)

  return json({
    day: today,
    tzOffsetMinutes: offset,
    generatedAt: new Date().toISOString(),
    trend,
    inputs: { meals: meals.length, functionalDays: metricHistory.length, gutDays: gutHistory.length, hasToday: !!todayCheckin, hasProfile: !!profileRes.data },
    ...result,
  })
})
