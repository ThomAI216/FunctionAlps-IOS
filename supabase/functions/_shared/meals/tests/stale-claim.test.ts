// A killed isolate writes no failure patch, so the stale-claim path must enforce the attempt budget itself.
import { assertEquals } from "jsr:@std/assert@1"
import { MAX_ATTEMPTS, staleClaimExhausted } from "../meal-analysis.ts"

Deno.test("a stale claim with the budget spent goes to the member", () => {
  assertEquals(staleClaimExhausted({ analysis_status: "pricing", analysis_attempts: MAX_ATTEMPTS }), true)
  assertEquals(staleClaimExhausted({ analysis_status: "identifying", analysis_attempts: MAX_ATTEMPTS + 3 }), true)
})

Deno.test("a stale claim with budget left is retried", () => {
  assertEquals(staleClaimExhausted({ analysis_status: "pricing", analysis_attempts: MAX_ATTEMPTS - 1 }), false)
  assertEquals(staleClaimExhausted({ analysis_status: "identifying", analysis_attempts: null }), false)
})

Deno.test("queued rows are bounded by the pick query, not here", () => {
  assertEquals(staleClaimExhausted({ analysis_status: "queued", analysis_attempts: MAX_ATTEMPTS }), false)
})
