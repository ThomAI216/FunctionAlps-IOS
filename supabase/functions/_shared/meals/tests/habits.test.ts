// Meal habits (habits.ts): the same correction on two photo meals becomes a habit, applied before pricing and marked
// `from_habit`; undone on two meals, it is dropped; a clinic row needs no history; text meals are never touched.
import { assert, assertEquals } from "jsr:@std/assert@1"
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import {
  applyHabits,
  applyHabitsToIdentification,
  isPhotoOnlyInput,
  learnHabits,
  loadHabits,
  ruleFromRow,
  withMealHabits,
  type HabitFood,
  type HabitHistoryEntry,
  type HabitItem,
  type HabitRule,
} from "../habits.ts"
import { completionPatch, emptyPriced, type IdentifySuccess } from "../meal-analysis.ts"

const f = (name: string, grams: number): HabitFood => ({ name, grams })
const meal = (modelList: HabitFood[], finalList: HabitFood[], applied: string[] = []): HabitHistoryEntry => ({ modelList, finalList, applied })
const item = (name: string, grams: number): HabitItem => ({ name, estimated_grams: grams, flags: [] })
const byKey = (rules: HabitRule[]) => Object.fromEntries(rules.map((r) => [r.key, r]))

// The model reads yogurt; the member says kefir.
const yogurtToKefir = (g = 150) => meal([f("plain yogurt", g), f("granola", 40)], [f("kefir", g), f("granola", 40)])

Deno.test("replace: yogurt -> kefir after 2 meals, not after 1", () => {
  assertEquals(learnHabits([yogurtToKefir()]), [])
  const rules = learnHabits([yogurtToKefir(150), yogurtToKefir(200)])
  assertEquals(rules.length, 1)
  const r = rules[0]
  assertEquals([r.key, r.kind, r.trigger, r.item, r.itemName, r.support], ["replace:yogurt>kefir", "replace", "yogurt", "kefir", "kefir", 2])
  // The member never changed the portion, only the name: the model's grams stand.
  assertEquals(r.grams, null)
  const out = applyHabits([item("Plain yogurt", 180), item("blueberries", 60)], rules)
  assertEquals(out.applied, ["replace:yogurt>kefir"])
  assertEquals(out.items[0], { name: "kefir", estimated_grams: 180, flags: [], from_habit: true })
})

Deno.test("replace: a consistent portion of the new food is used; a name fix alone keeps the model's grams", () => {
  const own = (g: number, k: number) => meal([f("yogurt", g)], [f("kefir", k)])
  const rules = learnHabits([own(150, 250), own(180, 250)])
  assertEquals(rules[0].grams, 250)
  assertEquals(applyHabits([item("yogurt", 120)], rules).items[0].estimated_grams, 250)
})

Deno.test("add: milk when chia is present after 2 meals, at the median grams the member used", () => {
  const chia = (milk: number, other: string) =>
    meal([f("chia seeds", 20), f(other, 50)], [f("chia seeds", 20), f(other, 50), f("whole milk", milk)])
  assertEquals(learnHabits([chia(150, "kiwi")]), [])
  const rules = learnHabits([chia(150, "kiwi"), chia(200, "walnuts"), chia(180, "raspberries")])
  // chia co-occurred with milk 3 times; kiwi, walnuts, raspberries once each -> only chia qualifies.
  assertEquals(rules.map((r) => r.key), ["add:chia seed+milk"])
  assertEquals(rules[0].grams, 180)
  assertEquals(rules[0].itemName, "whole milk")
  const out = applyHabits([item("Chia seeds", 25), item("mango", 80)], learnHabits([chia(150, "kiwi"), chia(200, "kiwi")]))
  // Two triggers qualify for milk (chia, kiwi, 2 each): one rule, alphabetical tie -> chia.
  assertEquals(out.applied, ["add:chia seed+milk"])
  assertEquals(out.items[2], { name: "whole milk", estimated_grams: 175, flags: [], from_habit: true })
  // No chia on the plate -> nothing added.
  assertEquals(applyHabits([item("kiwi", 80)], learnHabits([chia(150, "kiwi"), chia(200, "walnuts")])).applied, [])
})

Deno.test("portion: oats 40 -> 60 after 2 consistent meals", () => {
  const oats = (from: number, to: number) => meal([f("rolled oats", from), f("banana", 100)], [f("rolled oats", to), f("banana", 100)])
  assertEquals(learnHabits([oats(40, 60)]), [])
  const rules = learnHabits([oats(40, 60), oats(45, 60)])
  assertEquals(rules.map((r) => [r.key, r.grams, r.direction]), [["portion:rolled oat", 60, "up"]])
  const out = applyHabits([item("rolled oats", 40), item("banana", 110)], rules)
  assertEquals(out.items, [{ name: "rolled oats", estimated_grams: 60, flags: [], from_habit: true }, item("banana", 110)])
  // Never the other way: a rule learned from "more" does not shrink a bigger portion.
  assertEquals(applyHabits([item("rolled oats", 90)], rules).applied, [])
  // And never within the noise band: 55 -> 60 is not a change worth marking.
  assertEquals(applyHabits([item("rolled oats", 55)], rules).applied, [])
})

Deno.test("portion: no rule from inconsistent directions, nor from the resolver's 10 g rounding", () => {
  const oats = (from: number, to: number) => meal([f("oats", from)], [f("oats", to)])
  assertEquals(learnHabits([oats(40, 60), oats(40, 25)]), [])
  assertEquals(learnHabits([oats(40, 60), oats(40, 25), oats(50, 30)]).map((r) => [r.key, r.direction, r.grams]), [["portion:oat", "down", 27.5]])
  // An unedited meal: 45 g priced as 50 g, twice.
  assertEquals(learnHabits([oats(45, 50), oats(45, 50)]), [])
})

Deno.test("undo twice drops a rule; once does not; a dropped rule needs 2 fresh meals to come back", () => {
  const key = "replace:yogurt>kefir"
  const learned = [yogurtToKefir(), yogurtToKefir()]
  // Habit applied, member put yogurt back.
  const undo = meal([f("yogurt", 150), f("granola", 40)], [f("yogurt", 150), f("granola", 40)], [key])
  // Habit applied and kept: the row shows kefir.
  const kept = meal([f("yogurt", 150), f("granola", 40)], [f("kefir", 150), f("granola", 40)], [key])
  assertEquals(learnHabits([...learned, undo]).map((r) => r.key), [key])
  assertEquals(learnHabits([...learned, undo, undo]), [])
  // Kept in between resets the count: the undos must come AFTER the last support.
  assertEquals(learnHabits([...learned, undo, kept, undo]).map((r) => r.key), [key])
  // Dropped, then one stray correction: still dropped. Two: back.
  assertEquals(learnHabits([...learned, undo, undo, yogurtToKefir()]), [])
  assertEquals(learnHabits([...learned, undo, undo, yogurtToKefir(), yogurtToKefir()]).map((r) => r.key), [key])

  // The same for an add (milk removed) and a portion (grams restored).
  const addKey = "add:chia seed+milk"
  const chia = meal([f("chia seeds", 20)], [f("chia seeds", 20), f("milk", 150)])
  const addUndo = meal([f("chia seeds", 20)], [f("chia seeds", 20)], [addKey])
  assertEquals(learnHabits([chia, chia, addUndo]).map((r) => r.key), [addKey])
  assertEquals(learnHabits([chia, chia, addUndo, addUndo]), [])
  const oats = meal([f("oats", 40)], [f("oats", 60)])
  const oatsUndo = meal([f("oats", 40)], [f("oats", 40)], ["portion:oat"])
  assertEquals(learnHabits([oats, oats, oatsUndo, oatsUndo]), [])
})

Deno.test("a kept habit is support, and settling it first keeps a second swap in the same meal learnable", () => {
  const add = "add:chia seed+milk"
  // Milk added by the habit and kept, AND the member swapped kiwi for mango: one removed, two added on the raw diff.
  const both = meal([f("chia seeds", 20), f("kiwi", 50)], [f("chia seeds", 20), f("milk", 150), f("mango", 50)], [add])
  const swap = meal([f("kiwi", 50), f("oats", 40)], [f("mango", 50), f("oats", 40)])
  const rules = byKey(learnHabits([both, swap]))
  assert(rules["replace:kiwi>mango"], "the swap is learned despite the kept habit item")
  assertEquals(rules["add:chia seed+milk"], undefined) // one kept application alone is 1 meal
})

Deno.test("clinic rule applies without any history; table rows win over learned ones", () => {
  const clinic = ruleFromRow({ kind: "add", trigger_norm: "porridge", item_name: "Ground flaxseed", item_grams: 10, source: "clinic" })
  assert(clinic)
  const out = applyHabits([item("porridge", 250)], [clinic])
  assertEquals(out.applied, ["add:porridge+ground flaxseed"])
  assertEquals(out.items[1], { name: "Ground flaxseed", estimated_grams: 10, flags: [], from_habit: true })
  // Invalid rows are refused, not guessed: an add without grams, a portion without grams, a key aliasKey cannot make.
  assertEquals(ruleFromRow({ kind: "add", trigger_norm: "porridge", item_name: "flax", item_grams: null, source: "clinic" }), null)
  assertEquals(ruleFromRow({ kind: "portion", trigger_norm: "oat", item_name: null, item_grams: 0, source: "clinic" }), null)
  assertEquals(ruleFromRow({ kind: "add", trigger_norm: "a+b", item_name: "flax", item_grams: 5, source: "clinic" }), null)
})

Deno.test("from_habit only on the items a habit touched", () => {
  const rules = learnHabits([yogurtToKefir(), yogurtToKefir()])
  const out = applyHabits([item("yogurt", 150), item("granola", 40), item("honey", 8)], rules)
  assertEquals(out.items.map((i) => i.from_habit === true), [true, false, false])
  assertEquals("from_habit" in out.items[1], false)
  // Nothing matched -> the list comes back as it was, nothing marked, nothing applied.
  const none = applyHabits([item("rice", 150)], rules)
  assertEquals(none, { items: [item("rice", 150)], applied: [] })
})

const ident = (items: HabitItem[]): IdentifySuccess => ({
  ok: true,
  dish_name: "Breakfast bowl",
  items,
  duplicates_dropped: 0,
  confidence: 0.8,
  coverage: "full",
  coverage_note: null,
  model: "test",
  elapsed_ms: 1,
})

Deno.test("resolution_meta.identified stays the model's list; habits_applied is recorded", () => {
  const rules = learnHabits([yogurtToKefir(), yogurtToKefir()])
  const withHabits = applyHabitsToIdentification(ident([item("yogurt", 150), item("granola", 40)]), rules)
  assertEquals(withHabits.items[0].name, "kefir")
  const patch = completionPatch(withHabits, emptyPriced(), 1, null) as { resolution_meta: Record<string, unknown> }
  assertEquals(patch.resolution_meta.identified, [{ name: "yogurt", grams: 150 }, { name: "granola", grams: 40 }])
  assertEquals(patch.resolution_meta.habits_applied, ["replace:yogurt>kefir"])
  // A meal without the habits step (text/voice) records neither key's habit marker.
  const plain = completionPatch(ident([item("yogurt", 150)]), emptyPriced(), 1, null) as { resolution_meta: Record<string, unknown> }
  assertEquals(plain.resolution_meta.identified, [{ name: "yogurt", grams: 150 }])
  assertEquals("habits_applied" in plain.resolution_meta, false)
})

// A db that fails the test if anything reads it.
const untouchable = new Proxy({}, { get: () => { throw new Error("db must not be read") } }) as unknown as SupabaseClient

Deno.test("text and voice meals are never touched, and never cost a query", async () => {
  const id = ident([item("yogurt", 150)])
  assertEquals(await withMealHabits(untouchable, id, { patientId: "p1", photo: false }), id)
  assertEquals(await withMealHabits(untouchable, id, { patientId: null, photo: true }), id)
  assertEquals(isPhotoOnlyInput({ imageBase64s: ["x"] }), true)
  assertEquals(isPhotoOnlyInput({ imageBase64: "x" }), true)
  assertEquals(isPhotoOnlyInput({ description: "yogurt and granola" }), false)
  assertEquals(isPhotoOnlyInput({ imageBase64s: ["x"], description: "it's kefir" }), false)
  assertEquals(isPhotoOnlyInput({ statedItems: [{ name: "kefir", grams: 150 }] }), false)
  assertEquals(isPhotoOnlyInput({ imageBase64s: ["x"], statedItems: [{ name: "kefir", grams: 150 }] }), false)
  assertEquals(isPhotoOnlyInput({ imageBase64s: [], description: "  " }), false)
})

// A PostgREST stand-in: every builder method returns the builder, awaiting it yields the canned result per table.
function fakeDb(results: Record<string, { data: unknown; error: { code?: string; message: string } | null }>) {
  const calls: string[] = []
  const db = {
    from(table: string) {
      const q: Record<string, unknown> = {}
      for (const m of ["select", "eq", "neq", "gte", "not", "order", "limit", "in"]) {
        q[m] = (...args: unknown[]) => {
          calls.push(`${table}.${m}(${args.map((a) => JSON.stringify(a)).join(",")})`)
          return q
        }
      }
      q.then = (ok: (v: unknown) => unknown) => Promise.resolve(results[table]).then(ok)
      return q
    },
  }
  return { db: db as unknown as SupabaseClient, calls }
}
const row = (identified: HabitFood[], final: HabitFood[], applied: string[] = []) => ({
  identified,
  ai_identified_foods: final.map((x) => ({ name: x.name, estimated_grams: x.grams, kcal: 1 })),
  habits_applied: applied,
})

Deno.test("loadHabits: learned (newest-first rows) merged with clinic rows; clinic wins; missing table is no rows", async () => {
  const meals = [row([f("yogurt", 150)], [f("kefir", 150)]), row([f("yogurt", 120)], [f("kefir", 120)])]
  const clinic = [{ kind: "replace", trigger_norm: "yogurt", item_name: "skyr", item_grams: null, source: "clinic" }]
  const a = fakeDb({ nb_meal_logs: { data: meals, error: null }, nb_patient_meal_habits: { data: clinic, error: null } })
  const rules = await loadHabits(a.db, "p1", { excludeMealId: "m1" })
  assertEquals(rules.map((r) => [r.key, r.fromTable]), [["replace:yogurt>skyr", true]])
  assert(a.calls.includes(`nb_meal_logs.neq("id","m1")`))
  assert(a.calls.includes(`nb_patient_meal_habits.eq("active",true)`))

  const b = fakeDb({
    nb_meal_logs: { data: meals, error: null },
    nb_patient_meal_habits: { data: null, error: { code: "PGRST205", message: "not in schema cache" } },
  })
  assertEquals((await loadHabits(b.db, "p1")).map((r) => r.key), ["replace:yogurt>kefir"])

  const c = fakeDb({
    nb_meal_logs: { data: null, error: { code: "57014", message: "statement timeout" } },
    nb_patient_meal_habits: { data: clinic, error: null },
  })
  assertEquals(await loadHabits(c.db, "p1"), [])

  // And through the call-site step: the photo meal gets the habit, the mark, and keeps the model's list.
  const out = await withMealHabits(b.db, ident([item("yogurt", 150)]), { patientId: "p1", photo: true, mealLogId: "m1" })
  assertEquals(out.items, [{ name: "kefir", estimated_grams: 150, flags: [], from_habit: true }])
  assertEquals(out.model_items, [item("yogurt", 150)])
  assertEquals(out.habits_applied, ["replace:yogurt>kefir"])
})

Deno.test("a clinic portion applies to a small food the learned 10 g bar would ignore (honey 15 -> 7 g)", () => {
  const rule = ruleFromRow({ kind: "portion", trigger_norm: "honey", item_name: null, item_grams: 7, active: true, source: "clinic" } as never)
  assert(rule)
  const out = applyHabits([{ name: "honey", estimated_grams: 15, flags: [] }], [rule])
  assertEquals(out.items[0].estimated_grams, 7)
  assertEquals(out.items[0].from_habit, true)
  assertEquals(out.applied, ["portion:honey"])
})
