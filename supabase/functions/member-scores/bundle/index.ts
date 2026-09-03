// index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// ../_shared/supabase.ts
import { createClient } from "npm:@supabase/supabase-js@2";
var SUPABASE_URL = Deno.env.get("SUPABASE_URL"), ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
function getBearerToken(req) {
  let authHeader = req.headers.get("Authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}
function createUserScopedClient(req) {
  let token = getBearerToken(req);
  return createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
    auth: { persistSession: !1, autoRefreshToken: !1 }
  });
}

// engine/data/health-details.ts
function mountain(value, invert = !1) {
  let pct = (invert ? 5 - value : value - 1) / 4 * 100;
  return Math.round(Math.max(0, Math.min(100, pct)));
}
var NEUTRAL_1_5 = 3, HEALTH_DETAILS = {
  digestion: {
    title: "Digestion",
    accentColor: "#0d9488",
    higherIsBetter: !0,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.digestion ?? NEUTRAL_1_5,
  },
  sleep: {
    title: "Sleep",
    accentColor: "#6366f1",
    higherIsBetter: !0,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.sleep ?? NEUTRAL_1_5,
  },
  stress: {
    title: "Stress",
    accentColor: "#e11d48",
    higherIsBetter: !1,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value, !0),
    getCurrentValue: (checkin) => checkin?.stress ?? NEUTRAL_1_5,
  },
  energy: {
    title: "Energy",
    accentColor: "#d97706",
    higherIsBetter: !0,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.energy ?? NEUTRAL_1_5,
  },
  inflammation: {
    title: "Inflammation",
    accentColor: "#0d9488",
    higherIsBetter: !1,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value, !0),
    getCurrentValue: (checkin) => checkin?.inflammation ?? NEUTRAL_1_5,
  },
  mood: {
    title: "Mood",
    accentColor: "#db2777",
    higherIsBetter: !0,
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.mood ?? NEUTRAL_1_5,
  }
};

// engine/data/nutrients.ts
var NUTRIENTS = [
  {
    key: "vitamin_d3",
    name: "Vitamin D3",
    groupKey: "vitamins",
    unit: "mcg",
    rdaMale: 50,
    rdaFemale: 50,
    consumed: 0,
  },
  {
    key: "vitamin_c",
    name: "Vitamin C",
    groupKey: "vitamins",
    unit: "mg",
    rdaMale: 90,
    rdaFemale: 75,
    consumed: 0,
  },
  {
    key: "vitamin_b12",
    name: "Vitamin B12",
    groupKey: "vitamins",
    unit: "mcg",
    rdaMale: 2.4,
    rdaFemale: 2.4,
    consumed: 0,
  },
  {
    key: "folate",
    name: "Folate (B9)",
    groupKey: "vitamins",
    unit: "mcg DFE",
    rdaMale: 400,
    rdaFemale: 400,
    consumed: 0,
  },
  {
    key: "vitamin_a",
    name: "Vitamin A",
    groupKey: "vitamins",
    unit: "mcg RAE",
    rdaMale: 900,
    rdaFemale: 700,
    consumed: 0,
  },
  {
    key: "vitamin_k2",
    name: "Vitamin K2",
    groupKey: "vitamins",
    unit: "mcg",
    rdaMale: 120,
    rdaFemale: 90,
    consumed: 0,
  },
  {
    key: "vitamin_e",
    name: "Vitamin E",
    groupKey: "vitamins",
    unit: "mg",
    rdaMale: 15,
    rdaFemale: 15,
    consumed: 0,
  },
  {
    key: "biotin",
    name: "Biotin (B7)",
    groupKey: "vitamins",
    unit: "mcg",
    rdaMale: 30,
    rdaFemale: 30,
    consumed: 0,
  },
  {
    key: "magnesium",
    name: "Magnesium",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 420,
    rdaFemale: 320,
    consumed: 0,
  },
  {
    key: "iron",
    name: "Iron",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 8,
    rdaFemale: 18,
    consumed: 0,
  },
  {
    key: "zinc",
    name: "Zinc",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 11,
    rdaFemale: 8,
    consumed: 0,
  },
  {
    key: "calcium",
    name: "Calcium",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 1e3,
    rdaFemale: 1e3,
    consumed: 0,
  },
  {
    key: "selenium",
    name: "Selenium",
    groupKey: "minerals",
    unit: "mcg",
    rdaMale: 55,
    rdaFemale: 55,
    consumed: 0,
  },
  {
    key: "iodine",
    name: "Iodine",
    groupKey: "minerals",
    unit: "mcg",
    rdaMale: 150,
    rdaFemale: 150,
    consumed: 0,
  },
  {
    key: "potassium",
    name: "Potassium",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 3400,
    rdaFemale: 2600,
    consumed: 0,
  },
  {
    key: "phosphorus",
    name: "Phosphorus",
    groupKey: "minerals",
    unit: "mg",
    rdaMale: 700,
    rdaFemale: 700,
    consumed: 0,
  },
  {
    key: "omega3",
    name: "Omega-3 (EPA + DHA)",
    groupKey: "fatty_acids",
    unit: "g",
    rdaMale: 1.6,
    rdaFemale: 1.1,
    consumed: 0,
  },
  {
    key: "ala",
    name: "ALA (Omega-3)",
    groupKey: "fatty_acids",
    unit: "g",
    rdaMale: 1.6,
    rdaFemale: 1.1,
    consumed: 0,
  },
  {
    key: "epa",
    name: "EPA (Omega-3)",
    groupKey: "fatty_acids",
    unit: "mg",
    rdaMale: 500,
    rdaFemale: 500,
    consumed: 0,
  },
  {
    key: "dha",
    name: "DHA (Omega-3)",
    groupKey: "fatty_acids",
    unit: "mg",
    rdaMale: 500,
    rdaFemale: 500,
    consumed: 0,
  },
  {
    key: "choline",
    name: "Choline",
    groupKey: "fatty_acids",
    unit: "mg",
    rdaMale: 550,
    rdaFemale: 425,
    consumed: 0,
  }
];
var NUTRIENT_KEY_TO_MICRO = {
  vitamin_d3: "vitamin_d_mcg",
  vitamin_c: "vitamin_c_mg",
  vitamin_a: "vitamin_a_mcg",
  vitamin_e: "vitamin_e_mg",
  vitamin_k2: "vitamin_k2_mcg",
  vitamin_b12: "b12_mcg",
  folate: "folate_mcg",
  biotin: "biotin_mcg",
  iron: "iron_mg",
  magnesium: "magnesium_mg",
  calcium: "calcium_mg",
  zinc: "zinc_mg",
  selenium: "selenium_mcg",
  iodine: "iodine_mcg",
  potassium: "potassium_mg",
  phosphorus: "phosphorus_mg",
  omega3: "omega3_g",
  epa: "epa_mg",
  dha: "dha_mg",
  ala: "ala_g",
  choline: "choline_mg"
};
function getConsumedFromLogs(meals) {
  let consumed = {};
  for (let [nutrientKey, microField] of Object.entries(NUTRIENT_KEY_TO_MICRO))
    consumed[nutrientKey] = meals.reduce((sum, m) => {
      let val = m.micros?.[microField];
      return sum + (typeof val == "number" ? val : 0);
    }, 0);
  return consumed;
}
function getOverallCoverage(sex = "female", consumedOverride) {
  let coverages = NUTRIENTS.map((n) => {
    let target = sex === "male" ? n.rdaMale : n.rdaFemale, consumed = consumedOverride?.[n.key] ?? n.consumed;
    return Math.min(consumed / target, 1);
  });
  return Math.round(coverages.reduce((a, b) => a + b, 0) / coverages.length * 100);
}
function getNutrientGaps(threshold = 0.7, sex = "female", maxGaps = 4, consumedOverride) {
  return NUTRIENTS.map((n) => {
    let target = sex === "male" ? n.rdaMale : n.rdaFemale, pct = (consumedOverride?.[n.key] ?? n.consumed) / target;
    return { ...n, pct };
  }).filter((n) => n.pct < threshold).sort((a, b) => a.pct - b.pct).slice(0, maxGaps);
}

// engine/utils/tdee.ts
var NEAT_FACTORS = {
  sedentary: 1.2,
  lightly_active: 1.35,
  moderately_active: 1.55,
  very_active: 1.7,
  extremely_active: 1.9
};
function harrisBenedictBMR(weightKg, heightCm, age, sex) {
  return sex === "male" ? 88.362 + 13.397 * weightKg + 4.799 * heightCm - 5.677 * age : 447.593 + 9.247 * weightKg + 3.098 * heightCm - 4.33 * age;
}
function katchMcArdleBMR(weightKg, bfPercent) {
  return 370 + 21.6 * (weightKg * (1 - bfPercent / 100));
}
function calculateBMR(weightKg, heightCm, age, sex, bfPercent) {
  return bfPercent != null && bfPercent > 0 ? katchMcArdleBMR(weightKg, bfPercent) : harrisBenedictBMR(weightKg, heightCm, age, sex);
}
function calculateTDEE(weightKg, heightCm, age, sex, activityLevel, bfPercent) {
  let bmr = calculateBMR(weightKg, heightCm, age, sex, bfPercent), factor2 = NEAT_FACTORS[activityLevel] ?? 1.55;
  return Math.round(bmr * factor2);
}
function getGoalOffset(goal, bfPercent) {
  return goal === "maintain" ? 0 : goal === "cut" ? bfPercent < 18 ? -300 : bfPercent <= 25 ? -400 : -500 : bfPercent > 25 ? 150 : bfPercent >= 18 ? 250 : 300;
}
function calculateGoalMacros(tdee, weightKg, sex, goal, bfPercent) {
  let offset = getGoalOffset(goal, bfPercent ?? 22), goalCalories = tdee + offset, proteinG = Math.round(weightKg * (sex === "female" ? 1.5 : 1.8)), proteinKcal = proteinG * 4, fatKcal = goalCalories * 0.4, fatG = Math.round(fatKcal / 9), carbsKcal = goalCalories - proteinKcal - fatKcal, carbsG = Math.max(0, Math.round(carbsKcal / 4));
  return {
    proteinG,
    carbsG,
    fatG,
    calories: Math.round(goalCalories)
  };
}

// engine/nutrition/snapshot.ts
function buildNutritionSnapshot({
  meals,
  sex,
  weightKg,
  heightCm,
  age,
  activityLevel,
  goal,
  bfPercent,
  customMacros,
  customCalorieOffset,
  dbMacroTargets
}) {
  let computedTdee = calculateTDEE(weightKg, heightCm, age, sex, activityLevel, bfPercent ?? null), calculated = calculateGoalMacros(computedTdee, weightKg, sex, goal, bfPercent ?? null), customApplied = customMacros ? {
    proteinG: customMacros.proteinG ?? calculated.proteinG,
    carbsG: customMacros.carbsG ?? calculated.carbsG,
    fatG: customMacros.fatG ?? calculated.fatG,
    calories: customMacros.calories ?? calculated.calories
  } : calculated, tdee = dbMacroTargets?.tdee ?? computedTdee, targets = dbMacroTargets ? {
    proteinG: dbMacroTargets.proteinG,
    carbsG: dbMacroTargets.carbsG,
    fatG: dbMacroTargets.fatG,
    calories: dbMacroTargets.calories
  } : customApplied, goalCalories = dbMacroTargets ? dbMacroTargets.calories : customCalorieOffset != null ? computedTdee + customCalorieOffset : customApplied.calories, consumedCalories = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedCalories ?? 0), 0)), consumedProtein = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedProtein ?? 0), 0)), consumedCarbs = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedCarbs ?? 0), 0)), consumedFat = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedFat ?? 0), 0)), consumedFiber = Math.round(meals.reduce((sum, meal) => sum + (meal.micros?.fiber_g ?? 0), 0)), consumedMicros = getConsumedFromLogs(meals), microPct = getOverallCoverage(sex, consumedMicros), microGaps = getNutrientGaps(0.7, sex, 10, consumedMicros), fiberTarget = Math.max(25, Math.round(targets.calories / 1e3 * 14));
  return {
    tdee,
    goalCalories,
    targets,
    consumed: {
      calories: consumedCalories,
      protein: consumedProtein,
      carbs: consumedCarbs,
      fat: consumedFat,
      fiber: consumedFiber,
      micros: consumedMicros
    },
    micronutrients: {
      overallPct: microPct,
      gaps: microGaps
    },
    fiberTarget
  };
}

// engine/theme/tokens.ts
var colors = { forestS: "#4A8A5C", forest: "#2E5438", charcoal: "#1A1A16", stone: "#7A796F" };

// engine/dates/local-day.ts
var clockOffsetMs = 0;
function setClockOffsetMinutes(minutes) {
  clockOffsetMs = minutes * 6e4;
}
function engineNow() {
  return new Date(Date.now() + clockOffsetMs);
}
function shiftToWallClock(iso) {
  return new Date(new Date(iso).getTime() + clockOffsetMs).toISOString();
}
function localDayISO(d = engineNow()) {
  let y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, "0"), day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// engine/theme/nutrition-macros.ts
var MACRO_HUES = { protein: "#E0654F", carbs: "#E8A23D", fat: "#6C8AE4" };

// engine/nutrition/macros-view.ts
var MACRO_RING_COLORS = {
  kcal: colors.forestS,
  protein: MACRO_HUES.protein,
  carbs: MACRO_HUES.carbs,
  fat: MACRO_HUES.fat
};
function buildMacroStats(snapshot) {
  let mk = (key, label, unit, current, target, color) => ({
    key,
    label,
    unit,
    current: Math.round(current),
    target: Math.round(target),
    color,
    pct: target > 0 ? current / target : 0
  });
  return [
    mk("kcal", "Calories", "", snapshot.consumed.calories, snapshot.goalCalories, MACRO_RING_COLORS.kcal),
    mk("protein", "Protein", "g", snapshot.consumed.protein, snapshot.targets.proteinG, MACRO_RING_COLORS.protein),
    mk("carbs", "Carbs", "g", snapshot.consumed.carbs, snapshot.targets.carbsG, MACRO_RING_COLORS.carbs),
    mk("fat", "Fat", "g", snapshot.consumed.fat, snapshot.targets.fatG, MACRO_RING_COLORS.fat)
  ];
}
function macroProximityScore(stats) {
  let pcf = stats.filter((m) => m.key !== "kcal");
  return pcf.length ? Math.round(pcf.reduce((s, m) => s + Math.min(1, m.pct), 0) / pcf.length * 100) : null;
}

// engine/health/functional-score.ts
var PILLAR_WEIGHTS = {
  vitality: 0.42,
  metabolic: 0.33,
  nutrition: 0.25
};
function functionalComposite(input) {
  let pillars = {
    vitality: input.vitality,
    metabolic: input.metabolic,
    nutrition: input.nutrition
  }, present = Object.keys(pillars).filter((k) => pillars[k] !== null), score = null;
  if (present.length) {
    let totalW = present.reduce((s, k) => s + PILLAR_WEIGHTS[k], 0), weighted = present.reduce((s, k) => s + pillars[k] * PILLAR_WEIGHTS[k], 0);
    score = Math.round(weighted / totalW);
  }
  let basis = "none";
  return present.length && (input.hasWearable ? basis = "checkins+nutrition+wearable" : pillars.nutrition !== null ? basis = "checkins+nutrition" : basis = "checkins"), { score, basis, pillars };
}

// engine/health/score-core.ts
function statusFor(value) {
  return value === null ? "watch" : value >= 67 ? "good" : value >= 34 ? "watch" : "bad";
}
function availableCaseScore(factors) {
  let present = factors.filter((f) => f.value !== null);
  if (present.length === 0) return null;
  let totalW = present.reduce((s, f) => s + f.weight, 0);
  if (totalW === 0) return null;
  let weighted = present.reduce((s, f) => s + f.value * f.weight, 0);
  return Math.round(weighted / totalW);
}
function factor(key, label, value, weight, detail) {
  return { key, label, value, weight, status: statusFor(value), detail };
}

// engine/health/meal-timing.ts
var clamp = (n) => Math.max(0, Math.min(100, n)), hourOf = (iso) => {
  let d = new Date(iso);
  return d.getHours() + d.getMinutes() / 60;
};
function mealTimingScore(meals) {
  if (!meals.length) return null;
  let hours = meals.map((m) => hourOf(m.timestamp)).sort((a, b) => a - b), first = hours[0], last = hours[hours.length - 1], breakfast = clamp(first <= 10 ? 100 : 100 - (first - 10) * (40 / 3)), lateNight = clamp(last <= 20 ? 100 : 100 - (last - 20) * 20);
  if (meals.length === 1) return Math.round((breakfast + lateNight) / 2);
  let span = last - first, windowScore = clamp(span <= 12 ? 100 : 100 - (span - 12) * 10);
  return Math.round((breakfast + lateNight + windowScore) / 3);
}

// engine/health/nutrition-score.ts
var clamp2 = (n) => Math.max(0, Math.min(100, n));
function mealQuality(s) {
  return clamp2((s.inflammation + s.glycemic + s.digestion) / 3);
}
function nutritionScore(input) {
  let scored = input.meals.filter((m) => m.scores != null), mealQ = scored.length ? Math.round(scored.reduce((s, m) => s + mealQuality(m.scores), 0) / scored.length) : null, timing = mealTimingScore(input.meals), factors = [
    factor("mealQuality", "Meal quality", mealQ, 0.3),
    factor("micro", "Micro coverage", input.microCoveragePct, 0.3),
    factor("macro", "Macro proximity", input.macroProximityPct, 0.25),
    factor("timing", "Meal timing", timing, 0.15)
  ];
  return { score: availableCaseScore(factors), factors };
}

// engine/health/metabolic-score.ts
var round = (n) => Math.round(n), mean = (xs) => xs.reduce((s, v) => s + v, 0) / xs.length;
function metabolicScore(input) {
  let scored = input.meals.map((m) => m.scores).filter((s) => s != null), mealIGD = scored.length ? round(mean(scored.map(mealQuality))) : null, inflammation = scored.length ? round(mean(scored.map((s) => s.inflammation))) : null, glycemic = scored.length ? round(mean(scored.map((s) => s.glycemic))) : null, digestion = null, fg = input.feltDigestion;
  fg !== null && mealIGD !== null ? digestion = round(0.65 * fg + 0.35 * mealIGD) : fg !== null ? digestion = fg : mealIGD !== null && (digestion = mealIGD);
  let factors = [
    factor("digestion", "Digestion", digestion, 0.2),
    factor("inflammation", "Inflammation", inflammation, 0.25),
    factor("glycemic", "Glycemic", glycemic, 0.25),
    factor("energy", "Energy", input.energyScore, 0.3)
  ];
  return { score: availableCaseScore(factors), factors };
}

// engine/health/vitality-score.ts
function vitalityScore(input) {
  let factors = [
    factor("energy", "Energy", input.energyScore, 0.25),
    factor("mood", "Mood", input.moodScore, 0.25),
    factor("sleep", "Sleep", input.sleepScore, 0.25),
    factor("stress", "Stress", input.stressScore, 0.25),
    factor("recovery", "Recovery", input.recoveryScore ?? null, 0.2)
  ];
  return { score: availableCaseScore(factors), factors };
}

// engine/health/gut-breakdown.ts
function gutScore(input) {
  let factors = [
    factor("comfort", "Digestion comfort", input.comfort, 0.4),
    factor("reactions", "Post-meal reactions", input.reactions, 0.3),
    factor("stool", "Stool quality", input.stool, 0.3)
  ];
  return { score: availableCaseScore(factors), factors };
}
var clampR = (n) => Math.max(0, Math.min(100, n));
function mealReactionsScore(meals) {
  let reacted = meals.filter((m) => typeof m.reactionOverall == "number");
  if (!reacted.length) return null;
  let per = reacted.map((m) => {
    let felt = m.reactionOverall * 10, disc = [m.reactionBloating, m.reactionGasBurden, m.reactionFullness].filter(
      (v) => typeof v == "number"
    ), penalty = disc.length ? disc.reduce((s, v) => s + v, 0) / disc.length * 3 : 0;
    return clampR(felt - penalty);
  });
  return Math.round(per.reduce((s, v) => s + v, 0) / per.length);
}

// engine/health/score-series.ts
function lastNDays(now, n) {
  return Array.from({ length: n }, (_, i) => {
    let d = new Date(now);
    return d.setDate(d.getDate() - (n - 1 - i)), d;
  });
}

// engine/checkin/marker-trends.ts
var FUNCTIONAL_MARKERS = [
  { key: "energy", label: "Energy", color: HEALTH_DETAILS.energy.accentColor },
  { key: "sleep", label: "Sleep", color: HEALTH_DETAILS.sleep.accentColor },
  { key: "mood", label: "Mood", color: HEALTH_DETAILS.mood.accentColor },
  { key: "stress", label: "Calmness", color: HEALTH_DETAILS.stress.accentColor }
];
var clamp01 = (v) => Math.min(1, Math.max(0, v));
function freqBadness(perDay) {
  return perDay >= 1 && perDay <= 3 ? 0 : perDay === 0 ? 0.6 : perDay <= 5 ? 0.3 : 1;
}
function gutMarkerScore(key, v) {
  if (v == null) return null;
  switch (key) {
    case "bloating":
    case "burns":
      return Math.round((1 - clamp01((v - 1) / 9)) * 100);
    case "gasBurden":
      return Math.round((1 - clamp01(v / 10)) * 100);
    case "stoolQuality":
      return Math.round(clamp01((v - 1) / 4) * 100);
    case "stoolFrequency":
      return Math.round((1 - freqBadness(v)) * 100);
    default:
      return null;
  }
}

// engine/health/gut-signals.ts
function mean2(vals) {
  let v = vals.filter((x) => x !== null);
  return v.length ? Math.round(v.reduce((s, x) => s + x, 0) / v.length) : null;
}
function gutSignalsForEntry(entry, meals) {
  let comfort = entry?.comfort ?? null, stool = entry?.stool ?? null;
  return stool == null && entry && (stool = mean2([gutMarkerScore("stoolQuality", entry.stoolQuality), gutMarkerScore("stoolFrequency", entry.stoolFrequency)])), { comfort, stool, reactions: mealReactionsScore(meals) };
}
function latestGutEntry(today, history) {
  let all = today ? [...history, today] : history;
  if (!all.length) return null;
  let latest = (k) => {
    for (let i = all.length - 1; i >= 0; i--) {
      let v = all[i][k];
      if (typeof v == "number") return v;
    }
    return null;
  };
  return {
    date: "",
    bloating: latest("bloating"),
    burns: latest("burns"),
    gasBurden: latest("gasBurden"),
    stoolQuality: latest("stoolQuality"),
    stoolFrequency: latest("stoolFrequency"),
    comfort: latest("comfort"),
    gutOverall: latest("gutOverall"),
    stool: latest("stool")
  };
}
function gutSignalsCurrent(today, history, meals) {
  return gutSignalsForEntry(latestGutEntry(today, history), meals);
}

// engine/health/score-tip.ts
function ruleBasedTip(core) {
  let present = core.factors.filter((f) => f.value !== null);
  if (core.score === null || present.length === 0)
    return { summary: "Log a little more and your {label} reading appears here.", good: "", bad: "" };
  let sorted = [...present].sort((a, b) => b.value - a.value), best = sorted[0], worst = sorted[sorted.length - 1], summary = (
    core.score >= 67 ? "Your {label} is strong today." : core.score >= 34 ? "Your {label} is holding steady." : "Your {label} needs attention today."
  );
  if (present.length === 1)
    return { summary, good: `${best.label} (${best.value}/100) is the only signal so far.`, bad: "" };
  let good = `${best.label} is your strongest driver (${best.value}/100).`, bad = worst.value < 67 ? `${worst.label} is the weak point (${worst.value}/100) \xB7 focus here.` : "Nothing's dragging it down \xB7 keep it going.";
  return { summary, good, bad };
}

// engine/health/meal-window.ts
function windowMeals(meals, now) {
  if (!meals.length) return [];
  let dayKey = (d) => d.toDateString(), byDay = /* @__PURE__ */ new Map();
  for (let meal of meals) {
    let k = dayKey(new Date(meal.timestamp)), arr = byDay.get(k);
    arr ? arr.push(meal) : byDay.set(k, [meal]);
  }
  let today = byDay.get(dayKey(now));
  if (today && today.length) return today;
  let candidates = [...byDay.keys()].map((k) => ({ k, t: new Date(k).getTime() })).filter((x) => x.t <= now.getTime()).sort((a, b) => b.t - a.t);
  return candidates.length ? byDay.get(candidates[0].k) : [];
}

// engine/health/recovery-score.ts
var RECOVERY_WEIGHTS = { hrv: 0.3, sleepQuality: 0.25, felt: 0.25, stress: 0.2 }, FELT_RECOVERY_WEIGHTS = { recovery: 0.5, soreness: 0.25, physicalLoad: 0.125, mentalLoad: 0.125 }, clamp3 = (n, lo, hi) => Math.max(lo, Math.min(hi, n)), inv = (v) => v == null ? null : clamp3(100 - v, 0, 100);
function hrvFactorValue(today, baseline) {
  return today == null || baseline == null || baseline <= 0 ? null : Math.round(clamp3(50 + (today / baseline - 1) * 100 * 1.5, 0, 100));
}
function sleepQualityValue(hours, efficiencyPct) {
  let parts = [];
  return efficiencyPct != null && parts.push(clamp3(efficiencyPct, 0, 100)), hours != null && parts.push(hours >= 7.5 ? 95 : hours >= 7 ? 85 : hours >= 6.5 ? 70 : hours >= 6 ? 58 : hours >= 5 ? 45 : 32), parts.length ? Math.round(parts.reduce((s, v) => s + v, 0) / parts.length) : null;
}
function feltRecoveryScore(felt) {
  if (!felt) return null;
  let W = FELT_RECOVERY_WEIGHTS, factors = [
    factor("recovery", "Bounced back", felt.recovery ?? null, W.recovery),
    factor("soreness", "Freshness", inv(felt.soreness), W.soreness),
    factor("physicalLoad", "Physical load", inv(felt.physicalLoad), W.physicalLoad),
    factor("mentalLoad", "Mental load", inv(felt.mentalLoad), W.mentalLoad)
  ];
  return availableCaseScore(factors);
}
function recoveryScore(input) {
  let W = RECOVERY_WEIGHTS, factors = [
    factor("hrv", "HRV", hrvFactorValue(input.hrvRmssd, input.hrvBaseline), W.hrv),
    factor("sleepQuality", "Sleep quality", sleepQualityValue(input.sleepHours, input.sleepEfficiencyPct), W.sleepQuality),
    factor("felt", "How you feel", feltRecoveryScore(input.felt), W.felt),
    factor("stress", "Calm", inv(input.avgStress), W.stress)
  ];
  return { score: availableCaseScore(factors), factors };
}

// engine/health/trends-derive.ts
var OVERALL_FIELD = {
  energy: "energyOverall",
  mood: "moodScore",
  sleep: "sleepOverall",
  stress: "stressScore"
};
function feltMetric(entry, key) {
  if (!entry) return null;
  let field = OVERALL_FIELD[key];
  if (field !== void 0) {
    let o = entry[field];
    if (typeof o == "number") return o;
  }
  let cfg = HEALTH_DETAILS[key];
  return cfg.scoreFromValue(cfg.getCurrentValue(entry));
}
function mealsOnDay(meals, day) {
  let k = day.toDateString();
  return meals.filter((m) => new Date(m.timestamp).toDateString() === k);
}
function hasMicro(meals) {
  if (!meals.length) return !1;
  let consumed = getConsumedFromLogs(meals);
  return Object.values(consumed).some((v) => typeof v == "number" && v > 0);
}
function snapshotSafe(meals, p) {
  let weightKg = Number(p.weight), heightCm = Number(p.height);
  return !weightKg || !heightCm ? null : buildNutritionSnapshot({
    meals,
    sex: p.sex ?? "male",
    weightKg,
    heightCm,
    age: Number(p.age) || 34,
    activityLevel: p.activityLevel ?? "moderately_active",
    goal: p.goalMode ?? "maintain",
    bfPercent: p.estimatedBfPercent ?? 18,
    customMacros: p.customMacros ?? null,
    customCalorieOffset: p.customCalorieOffset ?? null
  });
}
function nutritionPcts(meals, p) {
  if (!meals.length) return { micro: null, macro: null };
  let snap = snapshotSafe(meals, p);
  return snap ? {
    micro: hasMicro(meals) ? snap.micronutrients.overallPct : null,
    macro: macroProximityScore(buildMacroStats(snap))
  } : { micro: null, macro: null };
}
var to100 = (v) => v == null ? null : Math.round(v / 10 * 100);
function feltFrom(src) {
  if (!src) return null;
  let s = src, f = { recovery: to100(s.recovery), soreness: to100(s.soreness), physicalLoad: to100(s.recentLoad), mentalLoad: to100(s.recentMentalLoad) };
  return Object.values(f).some((v) => v != null) ? f : null;
}
function recoveryFor(src, day, opts) {
  let w = opts.wearableByDay?.get(day) ?? null, felt = feltFrom(src);
  if (!w && !felt) return null;
  let hrvBaseline = opts.recoveryBaseline && opts.recoveryBaseline.hrvDays >= 14 ? opts.recoveryBaseline.hrvRmssd : null;
  return recoveryScore({
    hrvRmssd: w?.recovery?.hrvRmssd ?? null,
    hrvBaseline,
    sleepHours: w?.sleep?.hours ?? null,
    sleepEfficiencyPct: w?.sleep?.efficiencyPct ?? null,
    avgStress: w?.recovery?.avgStress ?? null,
    felt
  }).score;
}
function dayScores(dayMeals, fnEntry, gutEntry, p, recovery) {
  let energy = feltMetric(fnEntry, "energy"), vitality = fnEntry || recovery != null ? vitalityScore({ energyScore: energy, moodScore: feltMetric(fnEntry, "mood"), sleepScore: feltMetric(fnEntry, "sleep"), stressScore: feltMetric(fnEntry, "stress"), recoveryScore: recovery }).score : null, { micro, macro } = nutritionPcts(dayMeals, p), g = gutSignalsForEntry(gutEntry, dayMeals);
  return {
    vitality,
    metabolic: metabolicScore({ meals: dayMeals, feltDigestion: g.comfort, energyScore: energy }).score,
    nutrition: nutritionScore({ meals: dayMeals, microCoveragePct: micro, macroProximityPct: macro }).score,
    gut: gutScore({ comfort: g.comfort, stool: g.stool, reactions: g.reactions }).score
  };
}
function deriveTrends(input) {
  let { meals, metricHistory, gutHistory, today, checkin, profile, now } = input, todayFn = today?.todayFunctional ?? null, todayGut = today?.todayGut ?? null, win = windowMeals(meals, now), energyToday = feltMetric(todayFn, "energy"), { micro: winMicro, macro: winMacro } = nutritionPcts(win, profile), gutNow = gutSignalsCurrent(todayGut, gutHistory, win), isoDate = (d) => localDayISO(d), wopts = { wearableByDay: input.wearableByDay, recoveryBaseline: input.recoveryBaseline }, todayRecovery = recoveryFor(checkin, isoDate(now), wopts), vitalityCore = vitalityScore(
    todayFn || todayRecovery != null ? { energyScore: energyToday, moodScore: feltMetric(todayFn, "mood"), sleepScore: feltMetric(todayFn, "sleep"), stressScore: feltMetric(todayFn, "stress"), recoveryScore: todayRecovery } : { energyScore: null, moodScore: null, sleepScore: null, stressScore: null, recoveryScore: todayRecovery }
  ), metabolicCore = metabolicScore({ meals: win, feltDigestion: gutNow.comfort, energyScore: energyToday }), nutritionCore = nutritionScore({ meals: win, microCoveragePct: winMicro, macroProximityPct: winMacro }), gutCore = gutScore({ comfort: gutNow.comfort, stool: gutNow.stool, reactions: gutNow.reactions }), fnByDate = new Map(metricHistory.map((e) => [e.date, e])), gutByDate = new Map(gutHistory.map((e) => [e.date, e])), series = { vitality: [], metabolic: [], nutrition: [], gut: [] };
  for (let day of lastNDays(now, 14)) {
    let isToday = day.toDateString() === now.toDateString(), fnEntry = isToday ? todayFn : fnByDate.get(isoDate(day)) ?? null, gutEntry = isToday ? todayGut : gutByDate.get(isoDate(day)) ?? null, rec = recoveryFor(isToday ? checkin : fnEntry, isoDate(day), wopts), s = dayScores(mealsOnDay(meals, day), fnEntry, gutEntry, profile, rec);
    series.vitality.push(s.vitality), series.metabolic.push(s.metabolic), series.nutrition.push(s.nutrition), series.gut.push(s.gut);
  }
  let compositeSeries14d = series.vitality.map(
    (v, i) => functionalComposite({ vitality: v, metabolic: series.metabolic[i], nutrition: series.nutrition[i] }).score
  ), hasWearable = !!input.wearableByDay && input.wearableByDay.size > 0, composite = functionalComposite({ vitality: vitalityCore.score, metabolic: metabolicCore.score, nutrition: nutritionCore.score, hasWearable });
  compositeSeries14d.length && composite.score != null && (compositeSeries14d[compositeSeries14d.length - 1] = composite.score);
  let view = (core, label, s) => ({ ...core, series14d: s, tip: ruleBasedTip(core) });
  return {
    vitality: view(vitalityCore, "Vitality", series.vitality),
    metabolic: view(metabolicCore, "Metabolic", series.metabolic),
    nutrition: view(nutritionCore, "Nutrition", series.nutrition),
    gut: view(gutCore, "Gut", series.gut),
    composite,
    compositeSeries14d
  };
}

// engine/checkin/load-today.ts
var num = (v) => typeof v == "number" ? v : null;
function parseTodayCheckin(row, hasV2) {
  if (!row) return null;
  let functionalDoneAt = row.functional_completed_at ?? null, intelligenceDoneAt = row.intelligence_completed_at ?? null, date = row.checkin_date ?? "", fd = hasV2 ? row.functional_detail : null, functionalAnswers = fd && typeof fd == "object" ? fd : null, gd = hasV2 ? row.gut_detail : null, gutAnswers = gd && gd.answers && typeof gd.answers == "object" ? gd.answers : null, notes = gd && typeof gd.notes == "string" ? gd.notes : null, todayFunctional = functionalDoneAt ? {
    date,
    mood: num(row.mood),
    digestion: num(row.digestion),
    energy: num(row.energy),
    sleep: num(row.sleep),
    sleepQuality: num(row.sleep_quality),
    stress: num(row.stress),
    inflammation: num(row.inflammation),
    energyOverall: hasV2 ? num(row.energy_overall) : null,
    sleepOverall: hasV2 ? num(row.sleep_overall) : null,
    moodScore: hasV2 ? num(row.mood_score) : null,
    stressScore: hasV2 ? num(row.stress_score) : null,
    recovery: hasV2 ? num(row.recovery) : null,
    soreness: hasV2 ? num(row.soreness) : null,
    recentLoad: hasV2 ? num(row.recent_load) : null,
    recentMentalLoad: hasV2 ? num(row.recent_mental_load) : null
  } : null, todayGut = intelligenceDoneAt ? {
    date,
    bloating: num(row.bloating),
    burns: num(row.burns),
    gasBurden: num(row.gas_burden),
    stoolQuality: num(row.stool_quality),
    stoolFrequency: num(row.stool_frequency),
    comfort: hasV2 ? num(row.gut_comfort) : null,
    gutOverall: hasV2 ? num(row.gut_overall) : null,
    stool: hasV2 ? num(row.gut_stool) : null
  } : null;
  return { functionalDoneAt, intelligenceDoneAt, functionalAnswers, gutAnswers, notes, todayFunctional, todayGut };
}

// engine/health/overall-trend.ts
function overallTrend(series) {
  if (series.length < 2) return null;
  let half = Math.floor(series.length / 2), avg = (xs) => xs.reduce((s, v) => s + v, 0) / xs.length, delta = avg(series.slice(half)) - avg(series.slice(0, half));
  return delta >= 3 ? "up" : delta <= -3 ? "down" : "flat";
}

// index.ts
var CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
}, json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } }), TREND_DAYS = 13, MEAL_DAYS = 30, num2 = (v) => typeof v == "number" ? v : v != null && !Number.isNaN(Number(v)) ? Number(v) : null, und = (v) => v === null ? void 0 : v;
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body = {};
  try {
    body = await req.json();
  } catch {
  }
  let offset = Number.isFinite(body.tzOffsetMinutes) ? Math.max(-840, Math.min(840, Number(body.tzOffsetMinutes))) : 0;
  setClockOffsetMinutes(offset);
  let db = createUserScopedClient(req), { data: patientId, error: pidErr } = await db.rpc("current_member_patient_id");
  if (pidErr) return json({ error: pidErr.message }, 401);
  if (!patientId) return json({ error: "No patient profile for this account" }, 404);
  let now = engineNow(), today = localDayISO(now), dayCutoff = (back) => {
    let d = new Date(now);
    return d.setDate(d.getDate() - back), localDayISO(d);
  }, sinceMeals = new Date(Date.now() - MEAL_DAYS * 864e5).toISOString(), [mealsRes, reactionsRes, fnRes, gutRes, todayRes, profileRes] = await Promise.all([
    db.from("nb_meal_logs").select("id, name, meal_type, logged_at, total_calories, total_protein_g, total_carbs_g, total_fat_g, total_fiber_g, micronutrient_totals, inflammation_score, glycemic_score, gut_score, ai_identified_foods").eq("patient_id", patientId).gte("logged_at", sinceMeals).order("logged_at", { ascending: !0 }).limit(100),
    db.from("nb_meal_reactions").select("meal_log_id, overall, bloating, gas_burden, fullness, reaction_flags").eq("patient_id", patientId).gte("reaction_time", sinceMeals),
    db.from("patient_daily_checkins").select("checkin_date, mood, digestion, energy, sleep, sleep_quality, stress, inflammation, energy_overall, sleep_overall, mood_score, stress_score, recovery, soreness, recent_load, recent_mental_load").eq("patient_id", patientId).not("functional_completed_at", "is", null).lt("checkin_date", today).gte("checkin_date", dayCutoff(TREND_DAYS)).order("checkin_date", { ascending: !0 }).limit(TREND_DAYS + 1),
    db.from("patient_daily_checkins").select("checkin_date, bloating, burns, gas_burden, stool_quality, stool_frequency, gut_comfort, gut_overall, gut_stool").eq("patient_id", patientId).not("intelligence_completed_at", "is", null).lt("checkin_date", today).gte("checkin_date", dayCutoff(TREND_DAYS)).order("checkin_date", { ascending: !0 }).limit(TREND_DAYS + 1),
    db.from("patient_daily_checkins").select("checkin_date, functional_completed_at, intelligence_completed_at, mood, digestion, energy, sleep, sleep_quality, stress, inflammation, bloating, burns, gas_burden, stool_quality, stool_frequency, energy_overall, sleep_overall, mood_score, stress_score, gut_comfort, gut_overall, gut_stool, functional_detail, gut_detail, recovery, soreness, recent_load, recent_mental_load").eq("patient_id", patientId).eq("checkin_date", today).maybeSingle(),
    db.from("nb_patient_app_profiles").select("app_sex, app_weight_kg, app_height_cm, app_age, activity_level, goal_mode, estimated_body_fat_percent, macros_customized, target_calories, target_protein_g, target_carbs_g, target_fat_g, custom_calorie_offset_kcal").eq("patient_id", patientId).maybeSingle()
  ]);
  for (let r of [mealsRes, reactionsRes, fnRes, gutRes, todayRes, profileRes])
    if (r.error) return json({ error: r.error.message }, 500);
  let reactions = /* @__PURE__ */ new Map();
  for (let rr of reactionsRes.data ?? [])
    reactions.set(String(rr.meal_log_id), {
      overall: und(num2(rr.overall)),
      flags: Array.isArray(rr.reaction_flags) ? rr.reaction_flags : void 0,
      bloating: und(num2(rr.bloating)),
      gasBurden: und(num2(rr.gas_burden)),
      fullness: und(num2(rr.fullness))
    });
  let meals = (mealsRes.data ?? []).map((r) => {
    let items = Array.isArray(r.ai_identified_foods) ? r.ai_identified_foods : void 0, itemSum = (k) => items && items.length ? Math.round(items.reduce((a, it) => a + (typeof it[k] == "number" ? it[k] : 0), 0)) : void 0, hasScores = r.inflammation_score != null || r.glycemic_score != null || r.gut_score != null, reaction = reactions.get(String(r.id));
    return {
      id: String(r.id),
      dbId: String(r.id),
      name: r.name ?? "Meal",
      mealType: r.meal_type ?? "snack",
      estimatedCalories: itemSum("kcal") ?? und(num2(r.total_calories)),
      estimatedProtein: itemSum("protein_g") ?? und(num2(r.total_protein_g)),
      estimatedCarbs: itemSum("carbs_g") ?? und(num2(r.total_carbs_g)),
      estimatedFat: itemSum("fat_g") ?? und(num2(r.total_fat_g)),
      timestamp: shiftToWallClock(String(r.logged_at)),
      micros: { ...r.micronutrient_totals ?? {}, fiber_g: und(num2(r.total_fiber_g)) },
      scores: hasScores ? { inflammation: Number(r.inflammation_score ?? 0), glycemic: Number(r.glycemic_score ?? 0), digestion: Number(r.gut_score ?? 0) } : void 0,
      reactionOverall: reaction?.overall,
      reactionFlags: reaction?.flags,
      reactionBloating: reaction?.bloating,
      reactionGasBurden: reaction?.gasBurden,
      reactionFullness: reaction?.fullness,
      items
    };
  }), metricHistory = (fnRes.data ?? []).map((row) => ({
    date: row.checkin_date,
    mood: num2(row.mood),
    digestion: num2(row.digestion),
    energy: num2(row.energy),
    sleep: num2(row.sleep),
    sleepQuality: num2(row.sleep_quality),
    stress: num2(row.stress),
    inflammation: num2(row.inflammation),
    energyOverall: num2(row.energy_overall),
    sleepOverall: num2(row.sleep_overall),
    moodScore: num2(row.mood_score),
    stressScore: num2(row.stress_score),
    recovery: num2(row.recovery),
    soreness: num2(row.soreness),
    recentLoad: num2(row.recent_load),
    recentMentalLoad: num2(row.recent_mental_load)
  })), gutHistory = (gutRes.data ?? []).map((row) => ({
    date: row.checkin_date,
    bloating: num2(row.bloating),
    burns: num2(row.burns),
    gasBurden: num2(row.gas_burden),
    stoolQuality: num2(row.stool_quality),
    stoolFrequency: num2(row.stool_frequency),
    comfort: num2(row.gut_comfort),
    gutOverall: num2(row.gut_overall),
    stool: num2(row.gut_stool)
  })), todayCheckin = parseTodayCheckin(todayRes.data ?? null, !0), p = profileRes.data ?? {}, customised = p.macros_customized === !0, profile = {
    sex: p.app_sex === "male" || p.app_sex === "female" ? p.app_sex : null,
    weight: p.app_weight_kg != null ? String(p.app_weight_kg) : "",
    height: p.app_height_cm != null ? String(p.app_height_cm) : "",
    age: p.app_age != null ? String(p.app_age) : "",
    activityLevel: p.activity_level ?? null,
    goalMode: p.goal_mode === "build" || p.goal_mode === "cut" || p.goal_mode === "maintain" ? p.goal_mode : null,
    estimatedBfPercent: num2(p.estimated_body_fat_percent),
    customMacros: customised ? { proteinG: und(num2(p.target_protein_g)), carbsG: und(num2(p.target_carbs_g)), fatG: und(num2(p.target_fat_g)), calories: und(num2(p.target_calories)) } : null,
    customCalorieOffset: num2(p.custom_calorie_offset_kcal)
  }, result = deriveTrends({
    meals,
    metricHistory,
    gutHistory,
    today: todayCheckin,
    checkin: null,
    gutCompletedToday: !!todayCheckin?.intelligenceDoneAt,
    profile,
    now
  }), crownSeries = result.compositeSeries14d.filter((v) => v != null), trend = overallTrend(crownSeries);
  return json({
    day: today,
    tzOffsetMinutes: offset,
    generatedAt: (/* @__PURE__ */ new Date()).toISOString(),
    trend,
    inputs: { meals: meals.length, functionalDays: metricHistory.length, gutDays: gutHistory.length, hasToday: !!todayCheckin, hasProfile: !!profileRes.data },
    ...result
  });
});
