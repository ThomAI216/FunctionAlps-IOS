// Shapes lifted verbatim from lib/stores/log-store.ts (no zustand/supabase here).
export type FoodFlagKey = string
export type AnalyzedItem = {
  name: string
  estimated_grams?: number
  kcal?: number
  protein_g?: number
  carbs_g?: number
  fat_g?: number
  fiber_g?: number
  flags?: FoodFlagKey[]
  unpriced?: boolean
}
export interface MealMicros {
  vitamin_a_mcg?: number
  vitamin_c_mg?: number
  vitamin_d_mcg?: number
  vitamin_e_mg?: number
  vitamin_k2_mcg?: number
  biotin_mcg?: number
  iron_mg?: number
  magnesium_mg?: number
  calcium_mg?: number
  zinc_mg?: number
  omega3_g?: number
  epa_mg?: number
  dha_mg?: number
  ala_g?: number
  selenium_mcg?: number
  b12_mcg?: number
  folate_mcg?: number
  potassium_mg?: number
  phosphorus_mg?: number
  iodine_mcg?: number
  choline_mg?: number
  fiber_g?: number
}

export interface MealScores {
  inflammation: number
  glycemic: number
  digestion: number
}

export interface MealLog {
  id: string
  dbId?: string // nb_meal_logs row id (= id for DB-loaded meals; set post-save for session meals)
  name: string
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  estimatedCalories?: number
  estimatedProtein?: number
  estimatedCarbs?: number
  estimatedFat?: number
  portionDescription?: string
  timestamp: string
  /**
   * The patient's OWN WORDS about this meal (nb_meal_logs.patient_note). Every
   * other string on a MealLog — name, portionDescription, the scores' copy — is
   * the model's. This one is the person's, and the two are never merged or shown
   * under a shared label. See lib/meal-log/patient-note.ts.
   */
  patientNote?: string
  micros?: MealMicros
  scores?: MealScores // real reaction-signals from analyze-meal
  photoPath?: string // meal-images storage PATH (private bucket; sign via resolveMealPhotoUrl). Legacy rows hold a full public URL — the resolver handles both.
  reactionOverall?: number // post-meal felt-reaction 0–10 (nb_meal_reactions.overall)
  reactionFlags?: string[] // derived reaction tags (nb_meal_reactions.reaction_flags)
  reactionBloating?: number // nb_meal_reactions.bloating (0–10, higher = worse)
  reactionGasBurden?: number // nb_meal_reactions.gas_burden (0–10, higher = worse)
  reactionFullness?: number // nb_meal_reactions.fullness (0–10, higher = worse)
  items?: AnalyzedItem[] // per-ingredient breakdown (nb_meal_logs.ai_identified_foods)
}

