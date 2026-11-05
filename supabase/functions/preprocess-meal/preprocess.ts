// preprocess-meal — Infomaniak text model extracts structured food items from a
// voice transcript. STRICT-JSON output (no tool-calling), parsed here.
// Brought from FunctionAlps-APP (deployed v57) into the iOS repo on 2026-11-04; index.ts
// only serves this module, so the request and the parse can be unit-tested.
// No OpenAI: uses the Infomaniak AI product (same key as analyze-meal).
//
// ⚠⚠ THIS FILE WAS CORRECT AND UNDEPLOYED FOR FOUR MONTHS. ⚠⚠
// Until 2026-08-20 production ran v35 (deployed 2026-04-11): real OpenAI,
// `gpt-5.4-2026-03-05`, `OPENAI_API_KEY`. The sovereign rewrite lived only in
// git, so every spoken meal description a member recorded went to a US
// processor, against docs/wiki/pages/decisions/sovereign-ai-infomaniak.md.
// Found by the 2026-08-20 drift sweep, not by anything failing.
// ⇒ If you edit this file, DEPLOY it. A correct file nobody ships is not a fix.
//
// 2026-08-22: the OPTIONS are in the member's language too, not just the
// questions. The prompt used to localise only the question, so a French member
// answering "how much parmesan?" was offered "30 g (2 tbsp)" — Thomas caught it
// on the first French run. The client also repairs a stray English unit at
// render time (lib/meal-log/clarification.ts, localiseQuantityOption), because
// a prompt is a request and this needed a guarantee.
//
// 2026-08-21: clarifications are now TYPED — every one carries
// `kind: "identity" | "quantity"`, and a quantity option must be expressed in
// grams. Until this ships, the client falls back to reading the option shapes
// (lib/meal-log/clarification.ts) and nothing regresses; after it ships the
// member's answer lands in the right field because the model said which field
// it is. The client never stops classifying: the fallback covers a roll where
// the model omits the key, not just an old deploy.
//
// LANGUAGE. The member's app locale arrives as `locale` and decides the language
// of anything the member READS back (the clarification questions). It does NOT
// override what they SAID: food names stay in the spoken language, because
// "saumon" is what they will look for in the list they are about to check.
//
// 2026-11-04: Qwen 3.8, not Mistral-Small. Mistral was a workaround: Qwen 3.5 "thought" until it
// ran out of tokens because this call never sent `reasoning_effort: "none"`. It does now, and
// the model is chosen like every other sovereign call (SOVEREIGN_CHAT_MODEL, full id — the
// `qwen3` alias is retired by Infomaniak on 2026-11-23). The old INFOMANIAK_TEXT_MODEL secret is
// deliberately NOT read any more, so a forgotten Mistral value cannot keep this on Mistral.
const PRODUCT = Deno.env.get("INFOMANIAK_AI_PRODUCT_ID") ?? Deno.env.get("INFOMANIAK_PRODUCT_ID") ?? "108797"
const API_KEY = Deno.env.get("INFOMANIAK_AI_API_KEY")
export const TEXT_MODEL = Deno.env.get("SOVEREIGN_CHAT_MODEL") ?? "Qwen/Qwen3.8-27B-FP8"
const BASE = `https://api.infomaniak.com/2/ai/${PRODUCT}/openai/v1`

export const SYSTEM_PROMPT = `You are a food item extractor for a functional nutrition app. You receive a voice transcript of someone describing what they ate. The transcript may be in English or French.

YOUR TASK:
1. Detect the dominant language (en or fr).
2. Extract individual food items, ignoring filler words and conversational padding.
3. For each item, extract the food name and any mentioned quantity.
4. Rate confidence per item: "high" (clear), "medium" (could be misheard/ambiguous), "low" (unclear).
5. Add a clarification when you need something from the member. There are exactly TWO kinds and every clarification MUST say which it is:
   - "kind":"identity" — you are unsure WHICH FOOD it is. Options are 2-3 alternative foods.
   - "kind":"quantity" — you know the food but the member did not say HOW MUCH. Options are 2-3 portions.

RULES:
- French fillers to drop: "euh","genre","en fait","du coup","ben","bah","voilà","quoi","tu vois","j'ai mangé","j'ai pris","il y avait".
- English fillers to drop: "um","uh","like","you know","basically","I had","I ate","there was","so yeah".
- Keep food names in the ORIGINAL language (do not translate "saumon" to "salmon").
- Write clarification questions AND EVERY OPTION in the APP LANGUAGE given below,
  which is the language the member reads. If no app language is given, use the
  transcript's. This includes the measure inside a quantity option: a French
  member reads "30 g (2 c. à soupe)", NEVER "30 g (2 tbsp)".
- Group compound items: "chicken with rice and broccoli" = 3 items. Max 8 items.
- If all items are high-confidence AND every quantity is known, return an EMPTY clarifications array.
- A "quantity" option MUST be expressed IN GRAMS, with the familiar measure in parentheses when there is one. English: "30 g (2 tbsp)", "185 g (1 cup)", "30 g (a handful)". French: "30 g (2 c. à soupe)", "185 g (1 tasse)", "30 g (une poignée)". Never offer a portion the app cannot turn into grams.
- French measure vocabulary, use exactly these: c. à café · c. à soupe · tasse · verre · bol · tranche · poignée · morceau · boule · pincée · carré. Never leave an English unit in a French option.
- An option is NEVER a food name on a "quantity" clarification, and NEVER a portion on an "identity" one. The app writes an identity answer into the food's NAME and a quantity answer into its WEIGHT, so an option of the wrong sort lands in the wrong field.
- NEVER put a quantity inside a food name: the name is "parmigiano", never "parmigiano 30 g".

WEIGHT & VOLUME:
- ALWAYS provide estimated_g for every item (from the quantity or a standard portion).
- For grains/cereals/yogurt/liquids/rice/oats/sauces/soups also provide volume_measure (e.g. "1 cup","2 tbsp","1 bowl"); for solids it can be "".
- Standard portions: rice/pasta cooked 1 cup≈185g; oats dry 1/2 cup≈40g; yogurt 1 cup≈245g; milk 1 cup≈240g; olive oil 1 tbsp≈14g; nut butter 1 tbsp≈16g; berries 1 cup≈150g; leafy greens raw 1 cup≈30g; soup 1 bowl≈350g.

Respond with STRICT minified JSON only (no markdown, no prose), exactly this shape:
{"language":"en","cleaned_transcript":"...","items":[{"name":"...","quantity":"...","estimated_g":0,"volume_measure":"","confidence":"high"}],"clarifications":[{"item_index":0,"kind":"identity","question":"...","options":["...","..."]}]}`

function stripFences(s: string): string {
  return s.replace(/^\s*```(?:json)?/i, "").replace(/```\s*$/i, "").trim()
}

export type PreprocessInput = { transcript?: string; mealType?: string; locale?: string }
export type PreprocessResult = { status: number; body: Record<string, unknown> }

export async function preprocessTranscript(input: PreprocessInput): Promise<PreprocessResult> {
  if (!API_KEY) return { status: 500, body: { error: "INFOMANIAK_AI_API_KEY not configured in Supabase secrets" } }
  const { transcript, mealType, locale } = input
  if (!transcript || transcript.trim().length < 3) {
    return { status: 400, body: { error: "Transcript is too short or empty" } }
  }
  // An unrecognised value is ignored rather than trusted — the same rule
  // generate-score-tip used. Absent locale ⇒ the model falls back to detecting.
  const appLocale = locale === "en" || locale === "fr" ? locale : null
  const localeLine = appLocale
    ? `\n\nAPP LANGUAGE: ${appLocale === "fr" ? "French" : "English"}. Write every clarification question AND every option in ${appLocale === "fr" ? "French, addressing the member as \"vous\", with French measures (c. à soupe, tasse, poignée) and never English ones" : "English"}. Food names stay exactly as spoken.`
    : ""

  const userMessage = (mealType
    ? `Voice transcript for a ${mealType} meal:\n"${transcript.trim()}"`
    : `Voice transcript:\n"${transcript.trim()}"`) + localeLine

  const resp = await fetch(`${BASE}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: TEXT_MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage },
      ],
      temperature: 0.1,
      max_tokens: 900,
      stream: false,
      // Qwen 3.8 thinks by default; off, the JSON lands in message.content.
      reasoning_effort: "none",
      response_format: { type: "json_object" },
    }),
  })
  const raw = await resp.text()
  if (!resp.ok) {
    console.error("[preprocess-meal] Infomaniak error", resp.status, raw)
    return { status: 502, body: { error: "Preprocessing failed", status: resp.status, details: raw.slice(0, 500) } }
  }
  const msg = JSON.parse(raw)?.choices?.[0]?.message ?? {}
  let content = stripFences(String(msg.content ?? ""))
  if (!content && typeof msg.reasoning === "string") {
    // Qwen sometimes emits into `reasoning` despite reasoning_effort none (as in meal-analysis.ts).
    const m = msg.reasoning.match(/\{[\s\S]*\}/)
    if (m) content = m[0]
  }
  const result = JSON.parse(content)

  return {
    status: 200,
    body: {
      language: result.language ?? "en",
      cleanedTranscript: result.cleaned_transcript ?? transcript.trim(),
      items: (result.items ?? []).slice(0, 8),
      // `kind` is passed through UNVALIDATED on purpose: the client classifies
      // from the options whenever it is missing or unreadable, and it has to be
      // able to do that anyway for every app still talking to an older deploy.
      clarifications: result.clarifications ?? [],
    },
  }
}
