import { assertEquals, assertThrows } from "jsr:@std/assert@1"
import { AiPolicyError, aiPolicy, assertAiPolicy } from "../ai-policy.ts"

Deno.test("no vendor reaches a language model — deny by default", () => {
  for (const vendor of ["oura", "whoop", "polar", "garmin", "withings", "suunto", "google", "apple", "manual", "unknown-vendor"]) {
    assertEquals(aiPolicy({ vendor, transport: "vendor_direct", purpose: "llm_prompt" }), "deny")
    assertEquals(aiPolicy({ vendor, transport: "apple_health", purpose: "llm_training" }), "deny")
  }
})

Deno.test("deterministic scoring and the member's own display are allowed", () => {
  assertEquals(aiPolicy({ vendor: "oura", transport: "vendor_direct", metric: 3106, purpose: "scoring" }), "allow")
  assertEquals(aiPolicy({ vendor: "whoop", transport: "vendor_direct", purpose: "member_display" }), "allow")
  assertEquals(aiPolicy({ vendor: "apple", transport: "apple_health", purpose: "practitioner_view" }), "allow")
})

Deno.test("export and research need a legal decision; Oura is contractually deny", () => {
  assertEquals(aiPolicy({ vendor: "oura", transport: "vendor_direct", purpose: "export" }), "deny")
  assertEquals(aiPolicy({ vendor: "whoop", transport: "vendor_direct", purpose: "export" }), "legal_review_required")
  assertEquals(aiPolicy({ vendor: "apple", transport: "apple_health", purpose: "export" }), "allow")
  assertEquals(aiPolicy({ vendor: "withings", transport: "vendor_direct", purpose: "research" }), "legal_review_required")
  assertEquals(aiPolicy({ vendor: "oura", transport: "vendor_direct", purpose: "research" }), "deny")
})

Deno.test("assertAiPolicy throws a typed error carrying the verdict", () => {
  assertThrows(() => assertAiPolicy({ vendor: "oura", transport: "vendor_direct", purpose: "llm_prompt" }), AiPolicyError, "deny")
  assertAiPolicy({ vendor: "oura", transport: "vendor_direct", purpose: "scoring" })
})
