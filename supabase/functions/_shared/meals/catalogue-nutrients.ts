// STUB — the tests in tests/catalogue-nutrients.test.ts are written against this signature first.
import { FROM_CATALOGUE } from "./micro-keys.ts"

export type CatalogueLine = { food_item_id: string; grams: number }
export type CatalogueItem = {
  basis?: string
  estimated_grams?: number
  food_item_id?: string | null
  micros?: Record<string, number | null> | null
  components?: Array<{ grams: number; food_item_id: string | null }>
}
export type NutrientMetric = { value: number; status: "complete" | "partial"; coverage: number }
export type CatalogueMerge<T> = {
  items: T[]
  micronutrient_totals: Record<string, number>
  micro_coverage: {
    by_key: Record<string, number>
    below_limit: Record<string, number>
    catalogue_tracked: number
    catalogue_measured: number
  }
  nutrient_metrics?: Record<string, NutrientMetric>
  catalogue_version?: string
  catalogue_items: number
}

export function catalogueLines(_items: ReadonlyArray<CatalogueItem>): CatalogueLine[] {
  void FROM_CATALOGUE
  return []
}

export function mergeCatalogueNutrients<T extends CatalogueItem>(items: T[], _rpc: unknown): CatalogueMerge<T> {
  return {
    items,
    micronutrient_totals: {},
    micro_coverage: { by_key: {}, below_limit: {}, catalogue_tracked: 0, catalogue_measured: 0 },
    catalogue_items: 0,
  }
}
