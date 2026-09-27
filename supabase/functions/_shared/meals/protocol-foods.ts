// Protocol Lens matching engine — Deno mirror of the MATCHING HALF of
// `lib/health/protocol-foods.ts`.
//
// 🚨 CHANGE ONE, CHANGE BOTH. These are severity-tiered food term lists behind
// a clinical elimination protocol. A term added on one side and not the other
// means a patient on low-FODMAP is warned in the app and not in their data, or
// the reverse — and nothing fails loudly when that happens. The lib/ copy is
// the TESTED source of truth (`lib/health/__tests__/protocol-foods.test.ts`);
// this copy has no tests of its own and must never lead.
//
// WHY a copy at all: edge functions run in Deno and cannot import from `lib/`,
// which is a React-Native/Node tree with extensionless `@/` imports. It is the
// same reason `_shared/food-resolver.ts` inlines its pure modules and
// `generate-report/index.ts:479` already carries an inline copy of `isFlagged`
// + `PROTOCOL_META` from this very file.
//
// The clean end-state is the OTHER direction — `lib/health/protocol-foods.ts`
// re-exporting from here, exactly as `lib/meal-log/food-flags.ts` already
// imports `_shared/meal-flags.ts`. That is a client-side change with twelve
// importers and belongs in its own commit, not in an edge-function branch.
//
// Only the matching half is mirrored: no PROTOCOL_META, no isFlagged, no
// visibility helpers. Those are render-time decisions and no edge function
// makes them.
// Spec: docs/prd/2026-07-14-protocol-flagging-design.md

export type ProtocolKey = 'low_fodmap' | 'low_oxalate' | 'low_salicylate'
export type ProtocolSeverity = 'high' | 'moderate'
export type Strictness = 'strict' | 'relaxed'
export type PatientVisibility = 'silent' | 'soft' | 'coached'

export interface PatientProtocol {
  protocol_key: string // unknown keys are skipped (forward-compatible)
  strictness: Strictness
  patient_visibility: PatientVisibility
}

export interface ProtocolOverride {
  protocol_key: string
  food_term: string
  action: 'allow' | 'flag'
  severity?: ProtocolSeverity // action='flag' only; defaults high
}

export interface ProtocolFlag {
  item: string
  protocol: string
  severity: ProtocolSeverity
  matched_term: string
}

// ── Severity-tiered term lists ─────────────────────────────────────────────
// Seeded from Monash-style FODMAP references and standard oxalate/salicylate
// tables. Terms are lowercase and matched at WORD STARTS inside the item name
// (\b + term, prefix-open so 'cherr' catches cherry/cherries) — bare substring
// matching flags "steak" for 'tea' and "pineapple" for 'apple'. Append-with-
// care: avoid terms that are prefixes of unrelated foods ('bran' → branzino,
// 'corn' → corned beef); prefer the compound form ('wheat bran').
// Most-specific-term-wins: when a compound term and a bare term both match the
// same item (e.g. 'sweet potato' and 'potato'), only the longer (more specific)
// term's flag survives, so an override on the compound term isn't defeated by
// a leftover bare-term flag.

const TERMS: Record<ProtocolKey, { high: string[]; moderate: string[] }> = {
  low_fodmap: {
    high: [
      'onion', 'garlic', 'shallot', 'leek', 'wheat bread', 'wheat pasta', 'rye',
      'apple', 'pear', 'mango', 'watermelon', 'cherr', 'nectarine', 'peach', 'plum',
      'apricot', 'blackberr', 'honey', 'agave', 'high fructose',
      'milk', 'ice cream', 'soft cheese', 'ricotta', 'cottage cheese', 'yogurt',
      'cashew', 'pistachio', 'kidney bean', 'baked bean', 'black bean', 'chickpea',
      'hummus', 'lentil', 'soy milk', 'silken tofu', 'cauliflower', 'mushroom',
      'asparagus', 'artichoke', 'snow pea', 'sugar snap',
      'inulin', 'chicory', 'sorbitol', 'mannitol', 'xylitol',
    ],
    moderate: [
      'avocado', 'sweet potato', 'broccoli', 'brussels sprout', 'cabbage', 'celery',
      'sweetcorn', 'corn tortilla', 'beetroot', 'pomegranate', 'grapefruit', 'dried fruit',
      'raisin', 'date', 'fig', 'coconut milk', 'almond', 'almond milk', 'oat milk', 'sourdough',
      'green pea', 'fennel', 'okra', 'plantain', 'banana',
    ],
  },
  low_oxalate: {
    high: [
      'spinach', 'beet', 'beetroot', 'rhubarb', 'swiss chard', 'chard', 'almond',
      'almond milk', 'almond butter', 'cashew', 'peanut', 'sesame', 'tahini',
      'potato skin', 'sweet potato', 'okra', 'star fruit', 'buckwheat',
      'wheat bran', 'oat bran', 'quinoa', 'cocoa', 'chocolate', 'dark chocolate', 'soy flour',
      'black tea',
    ],
    moderate: [
      'potato', 'carrot', 'celery', 'parsnip', 'olives', 'kiwi', 'orange', 'fig',
      'raspberr', 'blackberr', 'brown rice', 'oatmeal', 'oats', 'lentil',
      'tomato sauce', 'walnut', 'pecan', 'hazelnut', 'green bean', 'leek',
    ],
  },
  low_salicylate: {
    high: [
      'berries', 'strawberr', 'raspberr', 'blueberr', 'blackberr', 'cranberr',
      'raisin', 'currant', 'dried fruit', 'apricot', 'orange', 'mandarin',
      'pineapple', 'grapes', 'tomato', 'tomato sauce', 'ketchup',
      'curry', 'paprika', 'cayenne', 'chili', 'turmeric', 'cumin', 'oregano',
      'thyme', 'rosemary', 'mint', 'peppermint', 'licorice', 'honey',
      'almond', 'wine', 'cider', 'vinegar', 'olive oil', 'coconut oil', 'tea',
    ],
    moderate: [
      'apple', 'avocado', 'cherr', 'grapefruit', 'kiwi', 'lemon', 'lime',
      'mango', 'melon', 'nectarine', 'peach', 'plum', 'watermelon', 'cucumber',
      'zucchini', 'courgette', 'sweet potato', 'spinach', 'mushroom', 'radish',
      'walnut', 'pistachio', 'macadamia', 'coffee',
    ],
  },
}

const norm = (s: string) => s.toLowerCase().trim()
const isKnown = (k: string): k is ProtocolKey => k in TERMS
const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
// Word-start prefix match: '\btea' hits "green tea" but not "steak";
// '\bcherr' hits "cherries" (prefix-open for plurals/inflections).
const wordStart = (name: string, term: string) => new RegExp(`\\b${escapeRe(term)}`).test(name)

// All matches, all severities — strictness is NOT applied here (see isFlagged
// in the lib/ copy). Overrides run last: 'allow' drops matches whose
// matched_term equals the override term; 'flag' adds a match when the term
// appears in the item name.
export function matchProtocols(
  items: { name: string }[],
  protocols: PatientProtocol[],
  overrides: ProtocolOverride[] = [],
): ProtocolFlag[] {
  const flags: ProtocolFlag[] = []
  for (const p of protocols) {
    if (!isKnown(p.protocol_key)) continue
    const lists = TERMS[p.protocol_key]
    const allow = new Set(
      overrides
        .filter((o) => o.protocol_key === p.protocol_key && o.action === 'allow')
        .map((o) => norm(o.food_term)),
    )
    const extraFlags = overrides.filter(
      (o) => o.protocol_key === p.protocol_key && o.action === 'flag',
    )
    for (const item of items) {
      const name = norm(item.name)
      if (!name) continue
      const seen = new Set<string>()
      const candidates: { term: string; severity: ProtocolSeverity }[] = []
      const collect = (term: string, severity: ProtocolSeverity) => {
        if (seen.has(term)) return
        seen.add(term)
        candidates.push({ term, severity })
      }
      for (const t of lists.high) if (wordStart(name, t)) collect(t, 'high')
      for (const t of lists.moderate) if (wordStart(name, t)) collect(t, 'moderate')
      for (const o of extraFlags) {
        const t = norm(o.food_term)
        if (t && wordStart(name, t)) collect(t, o.severity ?? 'high')
      }
      // Most-specific-term-wins: drop any candidate whose term is a substring
      // of another matched term on this same item (e.g. 'potato' shadowed by
      // 'sweet potato'), then apply 'allow' suppression on what remains.
      const shadowed = new Set(
        candidates
          .filter((a) => candidates.some((b) => b.term !== a.term && b.term.includes(a.term)))
          .map((a) => a.term),
      )
      for (const c of candidates) {
        if (shadowed.has(c.term) || allow.has(c.term)) continue
        flags.push({ item: item.name, protocol: p.protocol_key, severity: c.severity, matched_term: c.term })
      }
    }
  }
  return flags
}
