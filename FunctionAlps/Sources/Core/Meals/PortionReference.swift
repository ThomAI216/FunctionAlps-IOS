import Foundation

// Portions a member can actually picture — the Expo `lib/meal-log/portion-reference.ts`, the 32 families
// signed off by the owner (2026-08-21/22). Household measures for the food in front of the member, each
// carrying the grams it is worth; the only multiplier that survives is the fallback for an unrecognised food.
enum PortionReference {
    struct Option: Sendable, Equatable {
        /// The English source string; `localizedLabel` looks its translation up by this exact text.
        let label: String
        let grams: Int

        var localizedLabel: String { String(localized: String.LocalizationValue(label)) }
    }

    private struct Family {
        let id: String
        let match: NSRegularExpression
        let options: [Option]
        init(_ id: String, _ pattern: String, _ options: [(String, Int)]) {
            self.id = id
            self.match = try! NSRegularExpression(pattern: pattern)
            self.options = options.map { Option(label: $0.0, grams: $0.1) }
        }
    }

    // ORDER IS LOAD-BEARING: the first family whose pattern matches wins, so the specific sits above the general
    // (nut butter before fat, potato before fruit-whole, drink before fruit-whole, dried fruit before berries,
    // canned fish and charcuterie before protein, ice cream before dairy).
    private static let families: [Family] = [
        Family("nut-butter", #"\b(nut butter|peanut butter|almond butter|tahini|beurre de (cacahuete|arachide|amande)|pate a tartiner|nutella|purée d?'?amande|puree d?'?amande)\b"#,
               [("1 tsp", 6), ("1 tbsp", 16), ("2 tbsp", 32)]),
        Family("fat", #"\b(oil|olive oil|butter|ghee|lard|dripping|mayonnaise|huile|beurre|margarine|saindoux)\b"#,
               [("1 tsp", 5), ("1 tbsp", 14), ("2 tbsp", 28)]),
        Family("sweet-spread", #"\b(honey|jam|jelly|marmalade|syrup|maple|miel|confiture|gelee|sirop|marmelade)\b"#,
               [("1 tsp", 7), ("1 tbsp", 20), ("2 tbsp", 40)]),
        Family("condiment", #"\b(vinegar|salt|pepper|mustard|soy sauce|ketchup|harissa|tabasco|vinaigre|sel|poivre|moutarde|sauce soja|epice|epices|assaisonnement)\b"#,
               [("a pinch", 1), ("1 tsp", 5), ("1 tbsp", 15)]),
        Family("dip", #"\b(hummus|houmous|guacamole|tzatziki|tapenade|pesto|dip|tartinade)\b"#,
               [("1 tbsp", 25), ("2 tbsp", 50), ("a small bowl", 100)]),
        Family("cream", #"\b(cream|sour cream|creme|creme fraiche|mascarpone|chantilly)\b"#,
               [("1 tbsp", 15), ("2 tbsp", 30), ("a few tbsp", 60)]),
        Family("nuts", #"\b(nuts?|almonds?|walnuts?|cashews?|pistachios?|hazelnuts?|pecans?|seeds?|noix|amandes?|noisettes?|graines?|pistaches?|cajou|cacahuetes?)\b"#,
               [("a small handful", 15), ("a handful", 30), ("two handfuls", 60)]),
        Family("olives", #"\b(olives?)\b"#,
               [("a few", 15), ("a small handful", 30), ("a handful", 50)]),
        Family("grain-cooked", #"\b(rice|pasta|spaghetti|penne|noodles?|couscous|quinoa|bulgur|semolina|polenta|barley|spelt|millet|buckwheat|riz|pates|nouilles|semoule|boulgour|orge|epeautre|sarrasin)\b"#,
               [("half a cup", 90), ("1 cup", 185), ("1 and a half cups", 280)]),
        Family("legume-cooked", #"\b(lentils?|chickpeas?|beans?|peas|edamame|lentilles?|pois chiches?|haricots?|feves?|petits pois)\b"#,
               [("half a cup", 90), ("1 cup", 180), ("1 and a half cups", 270)]),
        Family("oats", #"\b(oats?|oatmeal|porridge|muesli|granola|flocons? d?'?avoine|avoine)\b"#,
               [("2 tbsp", 20), ("half a cup", 40), ("three quarters of a cup", 60)]),
        Family("ice-cream", #"\b(ice cream|gelato|sorbet|glace|creme glacee)\b"#,
               [("1 scoop", 50), ("2 scoops", 100), ("3 scoops", 150)]),
        Family("yogurt", #"\b(yogh?urt|yoghourt|skyr|quark|fromage blanc|yaourt|kefir)\b"#,
               [("half a cup", 120), ("1 cup", 245), ("1 and a half cups", 370)]),
        Family("wine", #"\b(wine|champagne|prosecco|vin|rose|mousseux)\b"#,
               [("a small glass", 100), ("1 glass", 150), ("2 glasses", 300)]),
        Family("beer", #"\b(beer|lager|ale|cider|biere|cidre)\b"#,
               [("a small beer", 250), ("1 beer", 330), ("a pint", 500)]),
        Family("drink", #"\b(milk|juice|smoothie|water|tea|coffee|lait|jus|eau|the|cafe|infusion|tisane)\b"#,
               [("half a glass", 120), ("1 glass", 240), ("a large glass", 350)]),
        Family("fruit-dried", #"\b(dried \w+|raisins secs|prunes?|pruneaux|dates?|dattes?|figs?|figues?|abricots secs|cranberries|fruits secs)\b"#,
               [("a few", 20), ("a small handful", 30), ("a handful", 45)]),
        Family("berries", #"\b(berries|berry|blueberr|strawberr|raspberr|blackberr|grapes|baies|myrtilles?|fraises?|framboises?|mures?|raisins?)\b"#,
               [("half a cup", 75), ("1 cup", 150), ("2 cups", 300)]),
        Family("leafy", #"\b(salad|lettuce|spinach|rocket|arugula|kale|greens|mesclun|salade|laitue|epinards?|roquette|chou kale|mache)\b"#,
               [("1 cup", 30), ("2 cups", 60), ("a large bowl", 100)]),
        Family("soup", #"\b(soup|broth|stew|bouillon|soupe|potage|veloute|ragout)\b"#,
               [("a small bowl", 200), ("1 bowl", 350), ("a large bowl", 500)]),
        Family("potato", #"\b(potato|potatoes|fries|chips|pomme de terre|pommes de terre|frites|patate|patates)\b"#,
               [("a small one", 90), ("a medium one", 150), ("a large one", 230)]),
        Family("avocado", #"\b(avocado|avocat)\b"#,
               [("a few slices", 40), ("half an avocado", 75), ("1 whole avocado", 150)]),
        Family("fruit-whole", #"\b(apple|banana|orange|pear|peach|nectarine|plum|kiwi|mango|apricot|clementine|mandarin|pomme|banane|poire|peche|prune|mangue|abricot|clementine|nectarine)\b"#,
               [("a small one", 100), ("a medium one", 150), ("a large one", 200)]),
        Family("vegetable", #"\b(carrots?|courgettes?|zucchini|broccoli|cauliflower|tomatoes?|tomato|cucumber|pepper|peppers|onions?|aubergines?|eggplant|green beans|leek|celery|pumpkin|squash|beetroot|carottes?|brocolis?|chou.?fleur|tomates?|concombre|poivrons?|oignons?|haricots verts|poireau|celeri|courge|potiron|betterave|legumes?)\b"#,
               [("a few spoonfuls", 60), ("a serving", 120), ("a large serving", 200)]),
        Family("canned-fish", #"\b(sardines?|mackerel|maquereaux?|anchovies|anchois|canned (tuna|fish|salmon)|tinned \w+|thon en boite|en conserve)\b"#,
               [("half a tin", 60), ("1 tin", 120), ("2 tins", 240)]),
        Family("charcuterie", #"\b(ham|salami|prosciutto|chorizo|bacon|pancetta|pastrami|jambon|saucisson|lardons|charcuterie|rillettes|pate)\b"#,
               [("1 slice", 25), ("2 slices", 50), ("a few slices", 80)]),
        Family("protein", #"\b(chicken|beef|pork|lamb|turkey|veal|steak|salmon|tuna|cod|fish|prawns?|shrimps?|tofu|tempeh|seitan|duck|poulet|boeuf|porc|agneau|dinde|veau|saumon|thon|cabillaud|poisson|crevettes?|canard|viande)\b"#,
               [("a small piece", 70), ("a palm-sized piece", 120), ("a large piece", 180)]),
        Family("cheese", #"\b(cheese|parmesan|parmigiano|cheddar|mozzarella|feta|gruy|brie|camembert|comte|roquefort|emmental|raclette|tomme|reblochon|ricotta|fromage|chevre|bleu)\b"#,
               [("a thin slice", 15), ("1 slice", 30), ("a generous piece", 50)]),
        Family("pastry", #"\b(croissant|cake|biscuit|biscuits|cookie|cookies|muffin|brownie|donut|doughnut|brioche|viennoiserie|gateau|tarte|pain au chocolat|madeleine|crepe|gaufre)\b"#,
               [("a small one", 30), ("1 piece", 60), ("a large piece", 100)]),
        Family("bread", #"\b(bread|toast|baguette|sourdough|rye|pita|wrap|tortilla|bun|roll|crouton|pain|tartine)\b"#,
               [("a thin slice", 25), ("1 slice", 35), ("2 slices", 70)]),
        Family("egg", #"\b(eggs?|omelette|omelet|oeufs?|œufs?)\b"#,
               [("1 egg", 50), ("2 eggs", 100), ("3 eggs", 150)]),
        Family("chocolate", #"\b(chocolate|chocolat|cacao)\b"#,
               [("1 square", 10), ("3 squares", 30), ("half a bar", 50)]),
    ]

    /// The last resort, and the ONLY place a multiplier survives.
    static let fallbackMultipliers: [(label: String, factor: Double)] = [
        ("a small portion", 0.6), ("a normal portion", 1), ("a large portion", 1.5),
    ]

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// Which family a food belongs to, or nil.
    static func family(for name: String) -> String? {
        let n = fold(name)
        let range = NSRange(n.startIndex..., in: n)
        return families.first { $0.match.firstMatch(in: n, range: range) != nil }?.id
    }

    /// Reference portions to offer for one food. `estimatedGrams` is used ONLY by the fallback.
    static func options(for name: String, estimatedGrams: Double) -> [Option] {
        let n = fold(name)
        let range = NSRange(n.startIndex..., in: n)
        if let f = families.first(where: { $0.match.firstMatch(in: n, range: range) != nil }) { return f.options }
        let base = estimatedGrams.isFinite && estimatedGrams > 0 ? estimatedGrams : 100
        return fallbackMultipliers.map { m in
            // 5 g steps: a chip reading "168 g" claims a precision nobody chose.
            Option(label: m.label, grams: max(5, Int(((base * m.factor) / 5).rounded()) * 5))
        }
    }

    /// Which offered portion the current grams correspond to (exact equality), or nil for a hand-set number.
    static func selectedLabel(_ options: [Option], grams: Double) -> String? {
        options.first { $0.grams == Int(grams.rounded()) }?.label
    }
}
