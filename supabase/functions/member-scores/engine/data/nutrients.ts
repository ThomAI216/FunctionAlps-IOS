export type NutrientGroupKey = 'vitamins' | 'minerals' | 'fatty_acids'

export interface NutrientGroup {
  key: NutrientGroupKey
  name: string
  emoji: string
  description: string
  whyItMatters: string
  topFoods: string
  color: string
  bgColor: string
  borderColor: string
}

export interface FoodSource {
  food: string
  amount: string
  emoji: string
}

export interface Nutrient {
  key: string
  name: string
  groupKey: NutrientGroupKey
  emoji: string
  unit: string
  tagline: string
  description: string
  rdaMale: number
  rdaFemale: number
  consumed: 0, // v1: starts at 0, updated from meal logs. _mockConsumed:number   // today (mock)
  weekTrend: number[] // 7-day values (Mon→Sun)
  foodSources: FoodSource[]
  deficiencySymptoms: string[]  // matches onboarding complaint keys
  aiSuggestion: string
}

export const NUTRIENT_GROUPS: NutrientGroup[] = [
  {
    key: 'vitamins',
    name: 'Vitamins',
    emoji: '💊',
    description: 'Organic compounds essential for growth, energy metabolism, immune function, and cellular repair. Most cannot be synthesised by the body · they must come from food.',
    whyItMatters: 'Vitamins act as cofactors in hundreds of enzymatic reactions. Even subclinical deficiencies can cause fatigue, poor immunity, skin issues, and neurological symptoms long before clinical signs appear.',
    topFoods: 'Leafy greens, organ meats, fish, eggs, citrus, fortified foods, sunlight (D3)',
    color: '#7c3aed',
    bgColor: '#f5f3ff',
    borderColor: '#ddd6fe',
  },
  {
    key: 'minerals',
    name: 'Minerals',
    emoji: '⚡',
    description: 'Inorganic elements required for bone structure, nerve transmission, fluid balance, enzyme function, and oxygen transport. Unlike vitamins, they cannot be created or broken down.',
    whyItMatters: 'Mineral deficiencies are among the most common nutritional issues in modern diets. Magnesium alone is involved in 300+ enzymatic reactions · low levels are linked to fatigue, muscle cramps, anxiety, and poor sleep.',
    topFoods: 'Nuts, seeds, legumes, leafy greens, seafood, dairy, whole grains',
    color: '#0369a1',
    bgColor: '#f0f9ff',
    borderColor: '#bae6fd',
  },
  {
    key: 'fatty_acids',
    name: 'Essential Fatty Acids',
    emoji: '🐟',
    description: 'Polyunsaturated fats that the body cannot produce on its own. Omega-3 (anti-inflammatory) and Omega-6 (pro-inflammatory) must be consumed in the right ratio · ideally 1:4 or less.',
    whyItMatters: 'Modern diets often skew 1:20 or worse Omega-3:Omega-6. This chronic imbalance drives systemic inflammation, poor cardiovascular health, brain fog, and mood instability.',
    topFoods: 'Fatty fish (salmon, sardines, mackerel), walnuts, flaxseeds, chia seeds',
    color: '#E2C25C',
    bgColor: '#FBF6E3',
    borderColor: '#EFE0AD',
  },
]

export const NUTRIENTS: Nutrient[] = [
  // ─── VITAMINS ───────────────────────────────────────────────
  {
    key: 'vitamin_d3',
    name: 'Vitamin D3',
    groupKey: 'vitamins',
    emoji: '☀️',
    unit: 'mcg',
    tagline: 'The sunshine vitamin',
    description: 'Vitamin D3 functions as a hormone, regulating calcium absorption, immune function, mood, and gene expression. Up to 80% of European adults are deficient, especially in winter.',
    rdaMale: 50, // mcg (= 2000 IU) — matches the vitamin_d_mcg meal-log field; was 2000 IU = ~0% coverage bug
    rdaFemale: 50, // mcg (= 2000 IU)
    consumed: 0,
    weekTrend: [7.5, 11, 6, 12.5, 9, 10, 7.5],
    foodSources: [
      { food: 'Salmon (85g)', amount: '14 mcg', emoji: '🐟' },
      { food: 'Sardines (90g)', amount: '9 mcg', emoji: '🐠' },
      { food: 'Egg yolk (1)', amount: '1.1 mcg', emoji: '🥚' },
      { food: 'Fortified milk (1 cup)', amount: '3 mcg', emoji: '🥛' },
    ],
    deficiencySymptoms: ['fatigue', 'mood_swings', 'joint_pain', 'anxiety', 'insomnia'],
    aiSuggestion: 'A salmon dinner tonight would add 570 IU. Combined with 20 min of midday sun, you\'d close this gap significantly.',
  },
  {
    key: 'vitamin_c',
    name: 'Vitamin C',
    groupKey: 'vitamins',
    emoji: '🍊',
    unit: 'mg',
    tagline: 'Master antioxidant',
    description: 'Essential for collagen synthesis, iron absorption, immune defence, and neutralising free radicals. The body excretes excess daily, so consistent intake is needed.',
    rdaMale: 90,
    rdaFemale: 75,
    consumed: 0,
    weekTrend: [65, 45, 85, 55, 70, 60, 50],
    foodSources: [
      { food: 'Red bell pepper (80g)', amount: '95mg', emoji: '🫑' },
      { food: 'Kiwi (1 fruit, 70g)', amount: '72mg', emoji: '🥝' },
      { food: 'Orange (1 medium, 130g)', amount: '70mg', emoji: '🍊' },
      { food: 'Broccoli (80g cooked)', amount: '51mg', emoji: '🥦' },
    ],
    deficiencySymptoms: ['fatigue', 'skin_issues', 'joint_pain'],
    aiSuggestion: 'Adding a red bell pepper to lunch would put you at 100%+ instantly.',
  },
  {
    key: 'vitamin_b12',
    name: 'Vitamin B12',
    groupKey: 'vitamins',
    emoji: '⚡',
    unit: 'mcg',
    tagline: 'Nerve & energy vitamin',
    description: 'Critical for red blood cell formation, DNA synthesis, and nervous system function. Vegans and vegetarians are at high risk of deficiency. Absorption declines with age.',
    rdaMale: 2.4,
    rdaFemale: 2.4,
    consumed: 0,
    weekTrend: [3.2, 1.8, 4.5, 2.0, 2.8, 1.5, 2.2],
    foodSources: [
      { food: 'Beef liver (85g)', amount: '70mcg', emoji: '🥩' },
      { food: 'Salmon (85g)', amount: '4.9mcg', emoji: '🐟' },
      { food: 'Eggs (2 large, 100g)', amount: '1.4mcg', emoji: '🥚' },
      { food: 'Greek yogurt (1 cup, 245g)', amount: '1.3mcg', emoji: '🫙' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog', 'mood_swings', 'anxiety'],
    aiSuggestion: 'You\'re at 75% today. Adding salmon or eggs to tomorrow\'s breakfast would push you above target.',
  },
  {
    key: 'folate',
    name: 'Folate (B9)',
    groupKey: 'vitamins',
    emoji: '🌿',
    unit: 'mcg DFE',
    tagline: 'Cell & DNA builder',
    description: 'Folate is essential for DNA replication, cell division, amino acid metabolism, and methylation reactions. Critical during pregnancy and for anyone with MTHFR variants.',
    rdaMale: 400,
    rdaFemale: 400,
    consumed: 0,
    weekTrend: [280, 320, 250, 380, 300, 270, 310],
    foodSources: [
      { food: 'Spinach (180g cooked)', amount: '263mcg', emoji: '🥬' },
      { food: 'Lentils (100g cooked)', amount: '179mcg', emoji: '🫘' },
      { food: 'Asparagus (6 spears, 90g)', amount: '134mcg', emoji: '🌿' },
      { food: 'Avocado (½, 70g)', amount: '82mcg', emoji: '🥑' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog', 'mood_swings'],
    aiSuggestion: 'A spinach + lentil bowl for lunch would bring you to 130% coverage in one meal.',
  },
  {
    key: 'vitamin_a',
    name: 'Vitamin A',
    groupKey: 'vitamins',
    emoji: '🥕',
    unit: 'mcg RAE',
    tagline: 'Vision & immune function',
    description: 'Vitamin A supports night vision, skin integrity, immune barriers, and cell differentiation. It exists as preformed (animal sources) and beta-carotene (plant sources).',
    rdaMale: 900,
    rdaFemale: 700,
    consumed: 0,
    weekTrend: [500, 850, 400, 1100, 600, 450, 700],
    foodSources: [
      { food: 'Sweet potato (1 medium, 130g)', amount: '1096mcg', emoji: '🍠' },
      { food: 'Carrots (80g)', amount: '459mcg', emoji: '🥕' },
      { food: 'Beef liver (85g)', amount: '6582mcg', emoji: '🥩' },
      { food: 'Spinach (90g cooked)', amount: '472mcg', emoji: '🥬' },
    ],
    deficiencySymptoms: ['skin_issues', 'fatigue'],
    aiSuggestion: 'Half a sweet potato at dinner would take you to 180% · A is fat-soluble, add olive oil to maximise absorption.',
  },
  {
    key: 'vitamin_k2',
    name: 'Vitamin K2',
    groupKey: 'vitamins',
    emoji: '🫀',
    unit: 'mcg',
    tagline: 'Calcium director',
    description: 'K2 activates proteins that direct calcium to bones (not arteries). Often deficient in Western diets. Works synergistically with D3 · both are needed together.',
    rdaMale: 120,
    rdaFemale: 90,
    consumed: 0,
    weekTrend: [25, 40, 15, 55, 30, 20, 35],
    foodSources: [
      { food: 'Natto (45g)', amount: '500mcg', emoji: '🫘' },
      { food: 'Gouda cheese (30g)', amount: '76mcg', emoji: '🧀' },
      { food: 'Egg yolks (2, 34g)', amount: '32mcg', emoji: '🥚' },
      { food: 'Pasture butter (15g)', amount: '15mcg', emoji: '🧈' },
    ],
    deficiencySymptoms: ['joint_pain'],
    aiSuggestion: 'K2 is tricky to get from diet. Adding gouda or a fermented food daily is the most practical strategy.',
  },
  {
    key: 'vitamin_e',
    name: 'Vitamin E',
    groupKey: 'vitamins',
    emoji: '🌻',
    unit: 'mg',
    tagline: 'Cell-protecting antioxidant',
    description: 'Vitamin E is a fat-soluble antioxidant that protects cell membranes from oxidative damage. It supports immune function, skin health, and cardiovascular protection. Works synergistically with Vitamin C.',
    rdaMale: 15,
    rdaFemale: 15,
    consumed: 0,
    weekTrend: [8, 12, 7, 14, 9, 10, 8],
    foodSources: [
      { food: 'Sunflower seeds (30g)', amount: '10mg', emoji: '🌻' },
      { food: 'Almonds (30g)', amount: '7.3mg', emoji: '🥜' },
      { food: 'Avocado (½, 70g)', amount: '2.1mg', emoji: '🥑' },
      { food: 'Spinach (180g cooked)', amount: '3.7mg', emoji: '🥬' },
    ],
    deficiencySymptoms: ['fatigue', 'skin_issues'],
    aiSuggestion: 'A handful of sunflower seeds or almonds as a snack covers most of your daily Vitamin E needs.',
  },
  {
    key: 'biotin',
    name: 'Biotin (B7)',
    groupKey: 'vitamins',
    emoji: '💅',
    unit: 'mcg',
    tagline: 'Hair, skin & metabolism',
    description: 'Biotin is a B-vitamin cofactor in carboxylase enzymes involved in fatty acid synthesis, gluconeogenesis, and amino acid metabolism. Widely known for supporting hair, skin, and nail health.',
    rdaMale: 30,
    rdaFemale: 30,
    consumed: 0,
    weekTrend: [22, 15, 28, 18, 25, 20, 16],
    foodSources: [
      { food: 'Beef liver (85g)', amount: '35mcg', emoji: '🥩' },
      { food: 'Eggs (2 large, 100g)', amount: '20mcg', emoji: '🥚' },
      { food: 'Salmon (85g)', amount: '5mcg', emoji: '🐟' },
      { food: 'Sweet potato (1 medium, 130g)', amount: '4.8mcg', emoji: '🍠' },
    ],
    deficiencySymptoms: ['skin_issues', 'fatigue'],
    aiSuggestion: 'Two eggs at breakfast cover about 66% of your biotin needs. Rare to be truly deficient unless on certain medications.',
  },

  // ─── MINERALS ───────────────────────────────────────────────
  {
    key: 'magnesium',
    name: 'Magnesium',
    groupKey: 'minerals',
    emoji: '💪',
    unit: 'mg',
    tagline: 'Master mineral · 300+ reactions',
    description: 'Magnesium is a cofactor in over 300 enzymatic reactions, including energy production, protein synthesis, muscle contraction, and nerve function. About 50% of people are deficient.',
    rdaMale: 420,
    rdaFemale: 320,
    consumed: 0,
    weekTrend: [200, 150, 250, 180, 220, 170, 190],
    foodSources: [
      { food: 'Spinach (180g cooked)', amount: '157mg', emoji: '🥬' },
      { food: 'Pumpkin seeds (30g)', amount: '156mg', emoji: '🎃' },
      { food: 'Dark chocolate (30g)', amount: '64mg', emoji: '🍫' },
      { food: 'Black beans (85g cooked)', amount: '60mg', emoji: '🫘' },
    ],
    deficiencySymptoms: ['fatigue', 'insomnia', 'anxiety', 'headaches', 'muscle_pain'],
    aiSuggestion: 'Spinach + pumpkin seeds tonight = ~313mg in one meal. That\'s 74% of your target in two ingredients.',
  },
  {
    key: 'iron',
    name: 'Iron',
    groupKey: 'minerals',
    emoji: '🩸',
    unit: 'mg',
    tagline: 'Oxygen transporter',
    description: 'Iron forms haemoglobin to carry oxygen through the body. Iron deficiency is the world\'s most common nutritional deficiency · women are particularly at risk. Heme iron (meat) absorbs 2-3x better than non-heme (plants).',
    rdaMale: 8,
    rdaFemale: 18,
    consumed: 0,
    weekTrend: [8, 6, 11, 7, 9, 7, 8],
    foodSources: [
      { food: 'Beef liver (85g)', amount: '5.8mg', emoji: '🥩' },
      { food: 'Lentils (100g cooked)', amount: '3.3mg', emoji: '🫘' },
      { food: 'Spinach (180g cooked)', amount: '3.2mg', emoji: '🥬' },
      { food: 'Dark chocolate (30g)', amount: '3.4mg', emoji: '🍫' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog'],
    aiSuggestion: 'Pair plant iron with Vitamin C to boost absorption by up to 6x. Lentils + lemon juice is a great combo.',
  },
  {
    key: 'zinc',
    name: 'Zinc',
    groupKey: 'minerals',
    emoji: '🔷',
    unit: 'mg',
    tagline: 'Immune & hormone support',
    description: 'Zinc is essential for immune function, wound healing, protein synthesis, DNA repair, and testosterone production. Depleted rapidly during stress or illness.',
    rdaMale: 11,
    rdaFemale: 8,
    consumed: 0,
    weekTrend: [7, 5, 10, 6, 8, 7, 6],
    foodSources: [
      { food: 'Oysters (85g)', amount: '74mg', emoji: '🦪' },
      { food: 'Beef (85g)', amount: '7mg', emoji: '🥩' },
      { food: 'Pumpkin seeds (30g)', amount: '2.2mg', emoji: '🎃' },
      { food: 'Chickpeas (85g cooked)', amount: '1.3mg', emoji: '🫘' },
    ],
    deficiencySymptoms: ['skin_issues', 'fatigue', 'digestive'],
    aiSuggestion: 'Beef or pumpkin seeds are your best non-supplement sources. Zinc from plants is less bioavailable · soak/sprout legumes to improve absorption.',
  },
  {
    key: 'calcium',
    name: 'Calcium',
    groupKey: 'minerals',
    emoji: '🦴',
    unit: 'mg',
    tagline: 'Bones, nerves & muscles',
    description: 'The most abundant mineral in the body · 99% stored in bones and teeth. Also critical for nerve transmission, muscle contraction, and blood clotting. Requires K2 and D3 for proper utilisation.',
    rdaMale: 1000,
    rdaFemale: 1000,
    consumed: 0,
    weekTrend: [650, 800, 500, 900, 700, 600, 750],
    foodSources: [
      { food: 'Greek yogurt (1 cup, 245g)', amount: '250mg', emoji: '🫙' },
      { food: 'Sardines with bones (85g)', amount: '325mg', emoji: '🐠' },
      { food: 'Kale (130g cooked)', amount: '177mg', emoji: '🥬' },
      { food: 'Cheddar cheese (30g)', amount: '204mg', emoji: '🧀' },
    ],
    deficiencySymptoms: ['muscle_pain', 'insomnia'],
    aiSuggestion: 'You\'re at 74%. Greek yogurt or sardines at dinner would push you past the target.',
  },
  {
    key: 'selenium',
    name: 'Selenium',
    groupKey: 'minerals',
    emoji: '🛡️',
    unit: 'mcg',
    tagline: 'Antioxidant & thyroid',
    description: 'Selenium is a component of powerful antioxidant enzymes and is essential for thyroid hormone synthesis and conversion (T4→T3). The EU population is often mildly deficient.',
    rdaMale: 55,
    rdaFemale: 55,
    consumed: 0,
    weekTrend: [35, 50, 25, 60, 40, 30, 45],
    foodSources: [
      { food: 'Brazil nuts (2 nuts, 8g)', amount: '80mcg', emoji: '🥜' },
      { food: 'Tuna (85g)', amount: '92mcg', emoji: '🐟' },
      { food: 'Turkey breast (85g)', amount: '27mcg', emoji: '🦃' },
      { food: 'Eggs (2 large, 100g)', amount: '28mcg', emoji: '🥚' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog'],
    aiSuggestion: '1-2 Brazil nuts per day covers your entire selenium requirement. The easiest nutritional upgrade you can make.',
  },
  {
    key: 'iodine',
    name: 'Iodine',
    groupKey: 'minerals',
    emoji: '🦋',
    unit: 'mcg',
    tagline: 'Thyroid health essential',
    description: 'Iodine is required for thyroid hormone production (T3 and T4), which controls metabolism, temperature, heart rate, and energy. Deficiency is a leading cause of hypothyroidism.',
    rdaMale: 150,
    rdaFemale: 150,
    consumed: 0,
    weekTrend: [80, 110, 60, 130, 90, 75, 100],
    foodSources: [
      { food: 'Nori seaweed (1 sheet, 3g)', amount: '50mcg', emoji: '🌿' },
      { food: 'Cod (85g)', amount: '99mcg', emoji: '🐟' },
      { food: 'Plain yogurt (1 cup, 245g)', amount: '75mcg', emoji: '🫙' },
      { food: 'Iodised salt (1.5g)', amount: '71mcg', emoji: '🧂' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog', 'mood_swings'],
    aiSuggestion: 'Make sure you\'re using iodised salt (not Himalayan or sea salt). Cod or yogurt daily would close this gap easily.',
  },
  {
    key: 'potassium',
    name: 'Potassium',
    groupKey: 'minerals',
    emoji: '🍌',
    unit: 'mg',
    tagline: 'Heart & fluid balance',
    description: 'Potassium maintains fluid balance, nerve signals, muscle contractions, and blood pressure. Most people get far less than the 3,500mg daily recommendation.',
    rdaMale: 3400,
    rdaFemale: 2600,
    consumed: 0,
    weekTrend: [1800, 2200, 1500, 2600, 2000, 1700, 1900],
    foodSources: [
      { food: 'Avocado (1 medium, 150g)', amount: '975mg', emoji: '🥑' },
      { food: 'Sweet potato (1 medium, 130g)', amount: '542mg', emoji: '🍠' },
      { food: 'Salmon (85g)', amount: '534mg', emoji: '🐟' },
      { food: 'Spinach (180g cooked)', amount: '839mg', emoji: '🥬' },
    ],
    deficiencySymptoms: ['fatigue', 'muscle_pain'],
    aiSuggestion: 'An avocado + sweet potato combo covers nearly 50% of your daily potassium in one meal.',
  },
  {
    key: 'phosphorus',
    name: 'Phosphorus',
    groupKey: 'minerals',
    emoji: '🔬',
    unit: 'mg',
    tagline: 'Bone builder & energy currency',
    description: 'Phosphorus is the second most abundant mineral in the body. It forms the backbone of DNA and ATP (cellular energy), builds bones alongside calcium, and buffers blood pH. Deficiency is rare but can occur with excessive antacid use.',
    rdaMale: 700,
    rdaFemale: 700,
    consumed: 0,
    weekTrend: [550, 700, 480, 800, 620, 580, 650],
    foodSources: [
      { food: 'Pumpkin seeds (30g)', amount: '332mg', emoji: '🎃' },
      { food: 'Salmon (85g)', amount: '214mg', emoji: '🐟' },
      { food: 'Lentils (100g cooked)', amount: '178mg', emoji: '🫘' },
      { food: 'Greek yogurt (1 cup, 245g)', amount: '220mg', emoji: '🫙' },
    ],
    deficiencySymptoms: ['fatigue', 'muscle_pain', 'joint_pain'],
    aiSuggestion: 'Most protein-rich foods are naturally high in phosphorus. If you eat adequate protein, you likely get enough phosphorus.',
  },

  // ─── FATTY ACIDS ───────────────────────────────────────────
  {
    key: 'omega3',
    name: 'Omega-3 (EPA + DHA)',
    groupKey: 'fatty_acids',
    emoji: '🐟',
    unit: 'g',
    tagline: 'Anti-inflammatory foundation',
    description: 'EPA and DHA are the active forms of Omega-3 · found primarily in fatty fish. EPA reduces inflammation, DHA supports brain structure and function. Conversion from ALA (plant sources) is only 5-10% efficient.',
    rdaMale: 1.6, // grams — matches the omega3_g meal-log field (was 1600 mg = ~0% coverage bug)
    rdaFemale: 1.1, // grams
    consumed: 0,
    weekTrend: [0.2, 1.5, 0.3, 0.15, 1.8, 0.25, 0.2],
    foodSources: [
      { food: 'Salmon (85g)', amount: '1800mg', emoji: '🐟' },
      { food: 'Sardines (85g)', amount: '1480mg', emoji: '🐠' },
      { food: 'Mackerel (85g)', amount: '2200mg', emoji: '🐡' },
      { food: 'Anchovies (30g)', amount: '750mg', emoji: '🐟' },
    ],
    deficiencySymptoms: ['brain_fog', 'joint_pain', 'mood_swings', 'skin_issues'],
    aiSuggestion: 'One serving of salmon covers your entire daily Omega-3 need. Aim for 2 fatty fish meals per week.',
  },
  {
    key: 'ala',
    name: 'ALA (Omega-3)',
    groupKey: 'fatty_acids',
    emoji: '🌱',
    unit: 'g',
    tagline: 'Plant-based Omega-3',
    description: 'Alpha-linolenic acid is the plant form of Omega-3. The body can convert it to EPA/DHA, but inefficiently. Still valuable for overall Omega-3 ratio improvement.',
    rdaMale: 1.6,
    rdaFemale: 1.1,
    consumed: 0,
    weekTrend: [0.8, 1.2, 0.6, 1.8, 1.0, 0.9, 1.1],
    foodSources: [
      { food: 'Chia seeds (1 tbsp, 12g)', amount: '2.5g', emoji: '🌱' },
      { food: 'Walnuts (30g)', amount: '2.6g', emoji: '🥜' },
      { food: 'Flaxseed (1 tbsp, 10g)', amount: '2.4g', emoji: '🌾' },
      { food: 'Hemp seeds (30g)', amount: '3g', emoji: '🌿' },
    ],
    deficiencySymptoms: ['brain_fog', 'mood_swings'],
    aiSuggestion: 'A tablespoon of chia or flaxseed in your morning smoothie covers your entire daily ALA target.',
  },
  {
    key: 'epa',
    name: 'EPA (Omega-3)',
    groupKey: 'fatty_acids',
    emoji: '🔥',
    unit: 'mg',
    tagline: 'Anti-inflammatory omega-3',
    description: 'Eicosapentaenoic acid (EPA) is the primary anti-inflammatory omega-3 fatty acid. It competes with arachidonic acid (omega-6) to reduce pro-inflammatory eicosanoid production. Found almost exclusively in marine sources.',
    rdaMale: 500,
    rdaFemale: 500,
    consumed: 0,
    weekTrend: [50, 700, 60, 40, 800, 50, 60],
    foodSources: [
      { food: 'Salmon (85g)', amount: '730mg', emoji: '🐟' },
      { food: 'Mackerel (85g)', amount: '760mg', emoji: '🐡' },
      { food: 'Sardines (85g)', amount: '430mg', emoji: '🐠' },
      { food: 'Herring (85g)', amount: '600mg', emoji: '🐟' },
    ],
    deficiencySymptoms: ['joint_pain', 'mood_swings', 'skin_issues'],
    aiSuggestion: 'One portion of salmon or mackerel exceeds your daily EPA target. Aim for 2-3 fatty fish meals per week.',
  },
  {
    key: 'dha',
    name: 'DHA (Omega-3)',
    groupKey: 'fatty_acids',
    emoji: '🧠',
    unit: 'mg',
    tagline: 'Brain & eye omega-3',
    description: 'Docosahexaenoic acid (DHA) is the most abundant omega-3 in brain tissue and retinal membranes. It is critical for cognitive function, visual acuity, and neuronal signalling. DHA needs increase during pregnancy and early childhood.',
    rdaMale: 500,
    rdaFemale: 500,
    consumed: 0,
    weekTrend: [70, 1000, 80, 60, 1100, 70, 80],
    foodSources: [
      { food: 'Salmon (85g)', amount: '1020mg', emoji: '🐟' },
      { food: 'Mackerel (85g)', amount: '1190mg', emoji: '🐡' },
      { food: 'Sardines (85g)', amount: '630mg', emoji: '🐠' },
      { food: 'Anchovies (30g)', amount: '310mg', emoji: '🐟' },
    ],
    deficiencySymptoms: ['brain_fog', 'mood_swings'],
    aiSuggestion: 'DHA is uniquely concentrated in fatty fish. Even one salmon meal provides 2x your daily target.',
  },
  {
    key: 'choline',
    name: 'Choline',
    groupKey: 'fatty_acids',
    emoji: '🫀',
    unit: 'mg',
    tagline: 'Liver & brain essential',
    description: 'Choline is required for cell membrane structure (phosphatidylcholine), neurotransmitter synthesis (acetylcholine), methyl donation, and liver fat metabolism. Over 90% of people do not meet the adequate intake.',
    rdaMale: 550,
    rdaFemale: 425,
    consumed: 0,
    weekTrend: [280, 350, 250, 400, 300, 320, 270],
    foodSources: [
      { food: 'Beef liver (85g)', amount: '356mg', emoji: '🥩' },
      { food: 'Eggs (2 large, 100g)', amount: '294mg', emoji: '🥚' },
      { food: 'Salmon (85g)', amount: '77mg', emoji: '🐟' },
      { food: 'Chicken breast (85g)', amount: '72mg', emoji: '🍗' },
    ],
    deficiencySymptoms: ['fatigue', 'brain_fog'],
    aiSuggestion: 'Two eggs provide ~60% of daily choline. It is one of the most under-consumed nutrients in modern diets.',
  },
]

// Helper: get all nutrients in a group
export function getNutrientsByGroup(groupKey: NutrientGroupKey): Nutrient[] {
  return NUTRIENTS.filter((n) => n.groupKey === groupKey)
}

// Helper: get a single nutrient
export function getNutrient(key: string): Nutrient | undefined {
  return NUTRIENTS.find((n) => n.key === key)
}

// Helper: get a group
export function getGroup(key: NutrientGroupKey): NutrientGroup | undefined {
  return NUTRIENT_GROUPS.find((g) => g.key === key)
}

// ─── Real consumed from meal logs ───────────────────────────────────────
// Maps nutrient keys to the micronutrient field names in MealMicros.
// When meals are logged from the food DB, their micronutrients are tracked.

import type { MealMicros } from '../types/log-store.ts'

export const NUTRIENT_KEY_TO_MICRO: Record<string, keyof MealMicros> = {
  vitamin_d3: 'vitamin_d_mcg',
  vitamin_c: 'vitamin_c_mg',
  vitamin_a: 'vitamin_a_mcg',
  vitamin_e: 'vitamin_e_mg',
  vitamin_k2: 'vitamin_k2_mcg',
  vitamin_b12: 'b12_mcg',
  folate: 'folate_mcg',
  biotin: 'biotin_mcg',
  iron: 'iron_mg',
  magnesium: 'magnesium_mg',
  calcium: 'calcium_mg',
  zinc: 'zinc_mg',
  selenium: 'selenium_mcg',
  iodine: 'iodine_mcg',
  potassium: 'potassium_mg',
  phosphorus: 'phosphorus_mg',
  omega3: 'omega3_g',
  epa: 'epa_mg',
  dha: 'dha_mg',
  ala: 'ala_g',
  choline: 'choline_mg',
}

/**
 * Sum consumed micronutrients from today's meal logs.
 * Returns a map of nutrient key → total consumed today.
 */
export function getConsumedFromLogs(meals: Array<{ micros?: MealMicros }>): Record<string, number> {
  const consumed: Record<string, number> = {}
  for (const [nutrientKey, microField] of Object.entries(NUTRIENT_KEY_TO_MICRO)) {
    consumed[nutrientKey] = meals.reduce((sum, m) => {
      const val = m.micros?.[microField]
      return sum + (typeof val === 'number' ? val : 0)
    }, 0)
  }
  return consumed
}

// Helper: calculate group average coverage percentage
export function getGroupCoverage(groupKey: NutrientGroupKey, sex: 'male' | 'female' = 'female', consumedOverride?: Record<string, number>): number {
  const nutrients = getNutrientsByGroup(groupKey)
  if (nutrients.length === 0) return 0
  const coverages = nutrients.map((n) => {
    const target = sex === 'male' ? n.rdaMale : n.rdaFemale
    const consumed = consumedOverride?.[n.key] ?? n.consumed
    return Math.min(consumed / target, 1)
  })
  return Math.round((coverages.reduce((a, b) => a + b, 0) / coverages.length) * 100)
}

// Helper: overall micronutrient coverage
export function getOverallCoverage(sex: 'male' | 'female' = 'female', consumedOverride?: Record<string, number>): number {
  const coverages = NUTRIENTS.map((n) => {
    const target = sex === 'male' ? n.rdaMale : n.rdaFemale
    const consumed = consumedOverride?.[n.key] ?? n.consumed
    return Math.min(consumed / target, 1)
  })
  return Math.round((coverages.reduce((a, b) => a + b, 0) / coverages.length) * 100)
}

// Helper: get nutrients below X% coverage
export function getNutrientGaps(
  threshold = 0.7,
  sex: 'male' | 'female' = 'female',
  maxGaps = 4,
  consumedOverride?: Record<string, number>
): (Nutrient & { pct: number })[] {
  return NUTRIENTS
    .map((n) => {
      const target = sex === 'male' ? n.rdaMale : n.rdaFemale
      const consumed = consumedOverride?.[n.key] ?? n.consumed
      const pct = consumed / target
      return { ...n, pct }
    })
    .filter((n) => n.pct < threshold)
    .sort((a, b) => a.pct - b.pct)
    .slice(0, maxGaps)
}

// (French overlay + React hooks removed for the edge runtime)
