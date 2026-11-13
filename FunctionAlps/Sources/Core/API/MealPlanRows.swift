import Foundation

// Wire shapes of the menus programme's RPCs and the two tables the recipe card reads. Decoded with
// `JSON.decode` (snake_case keys) and mapped onto `Models/MealPlan.swift`. Every field the server may leave
// out is optional: a thin row degrades to a plainer screen, never to a failed one.

enum MealPlanWire {
    // MARK: member_meal_plan

    struct Plan: Decodable, Sendable {
        let from: String?
        let to: String?
        let plans: [PlanRow]?
        let days: [DayRow]?

        var model: MealPlanRange {
            MealPlanRange(
                from: from ?? days?.first?.date ?? "", to: to ?? "",
                plans: (plans ?? []).map(\.model), days: (days ?? []).map(\.model)
            )
        }
    }

    struct PlanRow: Decodable, Sendable {
        let id: String
        let title: String?
        let startDate: String?
        let endDate: String?
        let people: Double?
        let showCalories: Bool?
        let allowSwaps: Bool?

        var model: PlanSummary {
            PlanSummary(id: id, title: title, startDate: startDate ?? "", endDate: endDate ?? "", people: people,
                        showCalories: showCalories ?? false, allowSwaps: allowSwaps ?? true)
        }
    }

    struct DayRow: Decodable, Sendable {
        let date: String
        let planId: String?
        let meals: [MealRow]?

        var model: PlanDay { PlanDay(date: date, planId: planId, meals: (meals ?? []).map(\.model)) }
    }

    struct RecipeRow: Decodable, Sendable {
        let id: String
        let title: String?
        let slug: String?
        let imagePath: String?
        let prepMinutes: Int?
        let cookMinutes: Int?
        let servings: Double?
        let variantKind: String?
        let own: Bool?
        let kcalPerServing: Double?

        var model: PlannedRecipe {
            PlannedRecipe(id: id, title: title ?? "", slug: slug, imagePath: imagePath, prepMinutes: prepMinutes,
                          cookMinutes: cookMinutes, servings: servings, variantKind: variantKind, own: own ?? false,
                          kcalPerServing: kcalPerServing)
        }
    }

    struct PrescribedRow: Decodable, Sendable {
        let id: String?
        let title: String?
    }

    struct MealRow: Decodable, Sendable {
        let slotId: String
        let momentUid: String?
        let moment: String?
        let mealType: String?
        let note: String?
        let portions: Double?
        let servings: Double?
        let swapped: Bool?
        let swapKind: String?
        let recipe: RecipeRow
        let prescribed: PrescribedRow?
        let excluded: Bool?
        let alternativeIds: [String]?
        let loggedMealId: String?

        var model: PlannedMeal {
            PlannedMeal(
                slotId: slotId, momentUid: momentUid, moment: moment,
                mealType: PlanLogic.mealType(mealType ?? moment),
                note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                portions: portions, servings: servings, swapped: swapped ?? false, swapKind: swapKind,
                recipe: recipe.model, prescribedId: prescribed?.id, prescribedTitle: prescribed?.title,
                excluded: excluded ?? false, alternativeIds: alternativeIds ?? [], loggedMealId: loggedMealId
            )
        }
    }

    // MARK: member_swap_candidates, member_swap_meal, member_log_planned_meal

    struct CandidateRow: Decodable, Sendable {
        let recipeId: String
        let title: String?
        let source: String?
        let variantKind: String?
        let prepMinutes: Int?
        let cookMinutes: Int?
        let imagePath: String?
        let isCurrent: Bool?

        var model: SwapCandidate {
            SwapCandidate(recipeId: recipeId, title: title ?? "", source: source.flatMap(SwapCandidate.Source.init(rawValue:)) ?? .library,
                          variantKind: variantKind, prepMinutes: prepMinutes, cookMinutes: cookMinutes,
                          imagePath: imagePath, isCurrent: isCurrent ?? false)
        }
    }

    struct SwapReply: Decodable, Sendable {
        let changed: Bool?
        let recipeId: String?
        let kind: String?

        var model: SwapOutcome { SwapOutcome(changed: changed ?? false, recipeId: recipeId, kind: kind) }
    }

    struct LogReply: Decodable, Sendable {
        let mealLogId: String
        let created: Bool?

        var model: PlannedMealLog { PlannedMealLog(mealLogId: mealLogId, created: created ?? true) }
    }

    // MARK: recipes + recipe_ingredients

    /// `steps` is a jsonb array of `{phase: "prep" | "cook", text}`; an older row holds plain strings.
    /// Anything else reads as no step.
    struct Step: Decodable, Sendable {
        let phase: String?
        let text: String?

        init(from decoder: any Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let s = try? single.decode(String.self) {
                phase = nil; text = s
            } else if let o = try? single.decode(StepObject.self) {
                phase = o.phase; text = o.text
            } else {
                phase = nil; text = nil
            }
        }

        private struct StepObject: Decodable, Sendable { let phase: String?; let text: String? }

        var model: RecipeStep? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
            return RecipeStep(phase: phase.flatMap(RecipeStep.Phase.init(rawValue:)), text: text)
        }
    }

    /// The numbers only: the micros and coverage dictionaries are counted, never read by key.
    struct NutritionRow: Decodable, Sendable {
        let kcal: Double?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        let fiberG: Double?
        let micros: [String: Double?]?
        let coverage: [String: Double?]?

        var model: RecipeNutrition {
            let present = (micros ?? [:]).values.compactMap { $0 }.count
            let cov = (coverage ?? [:]).values.map { $0 ?? 0 }
            return RecipeNutrition(
                kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG,
                measured: max(present, cov.filter { $0 > 0 }.count), total: cov.count,
                wellCovered: cov.filter { $0 >= 0.95 }.count
            )
        }
    }

    struct Recipe: Decodable, Sendable {
        let id: String
        let title: String?
        let bodyMd: String?
        let steps: [Step]?
        let servings: Double?
        let prepMinutes: Int?
        let cookMinutes: Int?
        let yieldText: String?
        let variantKind: String?
        let computedNutrition: NutritionRow?
        let whyLine: String?
        let description: String?

        private enum CodingKeys: String, CodingKey {
            case id, title, bodyMd, steps, servings, prepMinutes, cookMinutes, yieldText, variantKind, computedNutrition, whyLine, description
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            bodyMd = try c.decodeIfPresent(String.self, forKey: .bodyMd)
            // jsonb: an odd shape reads as "no steps" / "no nutrition", never as a lost recipe.
            steps = (try? c.decodeIfPresent([Step].self, forKey: .steps)) ?? nil
            servings = try? c.decodeIfPresent(Double.self, forKey: .servings)
            prepMinutes = try? c.decodeIfPresent(Int.self, forKey: .prepMinutes)
            cookMinutes = try? c.decodeIfPresent(Int.self, forKey: .cookMinutes)
            yieldText = try? c.decodeIfPresent(String.self, forKey: .yieldText)
            variantKind = try? c.decodeIfPresent(String.self, forKey: .variantKind)
            computedNutrition = (try? c.decodeIfPresent(NutritionRow.self, forKey: .computedNutrition)) ?? nil
            whyLine = (try? c.decodeIfPresent(String.self, forKey: .whyLine))?.nilIfEmpty
            description = (try? c.decodeIfPresent(String.self, forKey: .description))?.nilIfEmpty
        }

        func model(ingredients: [Ingredient]) -> RecipeCard {
            RecipeCard(
                id: id, title: title ?? "", bodyMd: bodyMd ?? "",
                steps: (steps ?? []).compactMap(\.model), whyLine: whyLine, description: description,
                servings: servings, prepMinutes: prepMinutes, cookMinutes: cookMinutes, yieldText: yieldText,
                variantKind: variantKind, ingredients: ingredients.map(\.model), nutrition: computedNutrition?.model
            )
        }
    }

    struct Ingredient: Decodable, Sendable {
        let id: String
        let rawText: String?
        let qty: Double?
        let unitCode: String?
        let isToTaste: Bool?
        let isOptional: Bool?
        let prepNote: String?

        var model: RecipeIngredient {
            RecipeIngredient(id: id, rawText: rawText ?? "", qty: qty, unitCode: unitCode, isToTaste: isToTaste ?? false,
                             isOptional: isOptional ?? false, prepNote: prepNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        }
    }

    // MARK: member_grocery_list

    struct Grocery: Decodable, Sendable {
        let planId: String?
        let periodStart: String?
        let periodEnd: String?
        let aisles: [AisleRow]?
        let custom: [CustomRow]?

        var model: GroceryList {
            GroceryList(planId: planId, periodStart: periodStart, periodEnd: periodEnd,
                        aisles: (aisles ?? []).map(\.model), custom: (custom ?? []).map(\.model))
        }
    }

    struct AisleRow: Decodable, Sendable {
        let code: String
        let label: String?
        let items: [ItemRow]?

        var model: GroceryAisle { GroceryAisle(code: code, label: label ?? code, items: (items ?? []).map(\.model)) }
    }

    struct BuyRow: Decodable, Sendable {
        let count: Int?
        let unit: String?
        let label: String?
    }

    struct UseRow: Decodable, Sendable {
        let date: String?
        let meal: String?
        let recipe: String?
    }

    struct ItemRow: Decodable, Sendable {
        let foodItemId: String
        let name: String?
        let qty: Double?
        let unit: String?
        let buy: BuyRow?
        let approxPieces: Int?
        let staple: Bool?
        let toTaste: Bool?
        let approx: Bool?
        let excluded: Bool?
        let `for`: [UseRow]?
        let insteadOf: [String]?
        let checked: Bool?
        let have: Bool?

        var model: GroceryItem {
            GroceryItem(
                foodItemId: foodItemId, name: name ?? "", qty: qty, unit: unit, buyCount: buy?.count, buyUnit: buy?.unit,
                buyLabel: buy?.label, approxPieces: approxPieces, staple: staple ?? false, toTaste: toTaste ?? false,
                approx: approx ?? false, excluded: excluded ?? false,
                uses: (`for` ?? []).map { GroceryUse(date: $0.date, meal: $0.meal, recipe: $0.recipe) },
                insteadOf: insteadOf ?? [], checked: checked ?? false, have: have ?? false
            )
        }
    }

    struct CustomRow: Decodable, Sendable {
        let id: String
        let label: String?
        let qtyText: String?
        let aisleCode: String?
        let checked: Bool?

        var model: GroceryCustomItem {
            GroceryCustomItem(id: id, label: label ?? "", qtyText: qtyText, aisleCode: aisleCode, checked: checked ?? false)
        }
    }
}

extension String {
    /// nil for an empty or blank string.
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
