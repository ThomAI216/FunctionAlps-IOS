#if DEBUG
import Foundation

/// The sample member the showcase screenshots show. Invented end to end: "Marie" (a first name only), three weeks
/// of check-ins drifting gently upward, ordinary meals, and an energy / focus / sleep plan. Every day is relative to
/// today, so the screenshots always look current.
enum ShowcaseData {
    static let patientId = "showcase-marie"
    static let userId = "showcase-user"
    static let heroMealId = "showcase-meal-lunch-1"
    static let actionHabitId = "showcase-h-strength"
    static let anatomyHabitId = "showcase-h-rhythm"
    static let breathCardId = "showcase-card-breath"
    static let articleSlug = "showcase-gut-feedback"

    static var calendar: Calendar { .current }
    static var now: Date { Date() }
    static func day(_ offset: Int) -> String { ISO8601.dayString(calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar) }
    static func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    /// A smooth climb with a little day-to-day texture, never random (the screenshots must be reproducible).
    static func curve(_ daysAgo: Int, from start: Double, to end: Double, wobble: Double = 4, phase: Double = 0) -> Int {
        let t = 1 - Double(daysAgo) / 20
        let base = start + (end - start) * max(0, min(1, t))
        return Int((base + wobble * sin(Double(daysAgo) * 1.7 + phase)).rounded())
    }

    // MARK: Profile

    static func profile(onboarded: Bool) -> MemberProfile {
        MemberProfile(
            sex: .female, age: 48, heightCm: 168, weightKg: 66, activityLevel: "moderate",
            healthGoals: ["energy", "focus", "sleep"], currentComplaints: ["low energy", "brain fog", "poor sleep"],
            dietaryPattern: "omnivore", targetCalories: 1900, targetProteinG: 105, targetCarbsG: 210, targetFatG: 68,
            goalMode: .maintain, onboardingCompletedAt: onboarded ? at(-24, 9) : nil, adultConfirmedAt: at(-24, 9), locale: "en"
        )
    }

    // MARK: Check-ins

    /// The last 21 days; today only once the evening check-in is done (the "done" screenshot).
    static func dailyCheckins(includeToday: Bool) -> [DailyCheckin] {
        (0...20).compactMap { ago -> DailyCheckin? in
            if ago == 0 && !includeToday { return nil }
            return DailyCheckin(
                day: day(-ago), functionalCompletedAt: at(-ago, 20, 40), gutCompletedAt: at(-ago, 20, 42),
                energy: curve(ago, from: 55, to: 78, phase: 0.3), mood: curve(ago, from: 58, to: 80, phase: 1.1),
                sleep: curve(ago, from: 52, to: 74, phase: 2.0), calmness: curve(ago, from: 50, to: 72, phase: 2.7),
                gutOverall: curve(ago, from: 56, to: 79, phase: 0.8)
            )
        }
    }

    static func eveningMoment() -> CheckinMoment {
        var m = CheckinMoment(slot: .evening, submittedAt: at(0, 20, 40))
        // Different reads on purpose (owner): mood good, energy in the middle, focus drained.
        m.energyBody = 52; m.energyMind = 22; m.energyStability = 45; m.energyOverall = 45
        m.moodScore = 84; m.stressScore = 40
        m.pills = ["worst_dip": ["afternoon"], "flavour_pos": ["content", "motivated"], "drivers": ["sleep", "movement"]]
        return m
    }

    static func gutHistory() -> [GutDay] {
        (1...20).map { ago in
            GutDay(day: day(-ago), comfort: curve(ago, from: 55, to: 80, phase: 0.5), stool: curve(ago, from: 60, to: 78, phase: 1.4),
                   reactions: curve(ago, from: 58, to: 82, phase: 2.2), overall: curve(ago, from: 56, to: 79, phase: 0.8),
                   stoolQuality: 4, stoolFrequency: 1, completedAt: at(-ago, 20, 42))
        }
    }

    // MARK: Meals

    private struct Plate {
        let type: MealLog.MealType, hour: Int, minute: Int, name: String, photo: String?
        let items: [MealItem], scores: MealScores
    }

    /// Public food photos stand in for the member's own; the hero lunch uses the plate bundled with the app.
    private static let porridge = "https://images.unsplash.com/photo-1517673400267-0251440c45dc?w=1200&q=80"
    private static let salmonBowl = "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=1200&q=80"
    private static let dinnerPlate = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1200&q=80"
    static let bundledPlate = "showcase/plate-demo.jpg"

    private static let breakfast = Plate(type: .breakfast, hour: 7, minute: 45, name: "Oat porridge with berries and walnuts", photo: porridge, items: [
        MealItem(name: "rolled oats", estimatedGrams: 50, kcal: 190, proteinG: 6.5, carbsG: 32, fatG: 3.4, fiberG: 5, flags: ["whole_grain", "fiber"]),
        MealItem(name: "blueberries", estimatedGrams: 80, kcal: 46, proteinG: 0.6, carbsG: 11.6, fatG: 0.3, fiberG: 1.9, flags: ["polyphenols"]),
        MealItem(name: "walnuts", estimatedGrams: 15, kcal: 98, proteinG: 2.3, carbsG: 2.1, fatG: 9.8, fiberG: 1, flags: ["omega3"]),
        MealItem(name: "Greek yoghurt", estimatedGrams: 100, kcal: 97, proteinG: 9, carbsG: 3.9, fatG: 5, flags: ["fermented"]),
    ], scores: MealScores(inflammation: 82, glycemic: 74, digestion: 86))

    private static let lunch = Plate(type: .lunch, hour: 12, minute: 40, name: "Quinoa bowl with chicken and roasted vegetables", photo: bundledPlate, items: [
        MealItem(name: "grilled chicken breast", estimatedGrams: 120, kcal: 198, proteinG: 37, carbsG: 0, fatG: 4.3),
        MealItem(name: "quinoa", estimatedGrams: 150, kcal: 180, proteinG: 6.6, carbsG: 32, fatG: 2.9, fiberG: 4.2, flags: ["whole_grain", "fiber"]),
        MealItem(name: "roasted courgette and peppers", estimatedGrams: 140, kcal: 70, proteinG: 2, carbsG: 9, fatG: 3.2, fiberG: 3, flags: ["plants", "fiber"]),
        MealItem(name: "spinach", estimatedGrams: 40, kcal: 9, proteinG: 1.2, carbsG: 1.4, fatG: 0.2, fiberG: 0.9, flags: ["leafy_greens"]),
        MealItem(name: "olive oil and lemon dressing", estimatedGrams: 12, kcal: 96, proteinG: 0, carbsG: 0.4, fatG: 10.6, flags: ["olive_oil"]),
    ], scores: MealScores(inflammation: 84, glycemic: 79, digestion: 81))

    private static let dinner = Plate(type: .dinner, hour: 19, minute: 30, name: "Baked salmon, sweet potato and green beans", photo: dinnerPlate, items: [
        MealItem(name: "baked salmon", estimatedGrams: 130, kcal: 270, proteinG: 28, carbsG: 0, fatG: 17, flags: ["omega3"]),
        MealItem(name: "sweet potato", estimatedGrams: 150, kcal: 129, proteinG: 2.4, carbsG: 30, fatG: 0.2, fiberG: 4.5, flags: ["fiber"]),
        MealItem(name: "green beans", estimatedGrams: 100, kcal: 31, proteinG: 1.8, carbsG: 7, fatG: 0.2, fiberG: 2.7, flags: ["plants"]),
    ], scores: MealScores(inflammation: 88, glycemic: 72, digestion: 80))

    private static let snack = Plate(type: .snack, hour: 10, minute: 30, name: "Apple and almonds", photo: nil, items: [
        MealItem(name: "apple", estimatedGrams: 150, kcal: 78, proteinG: 0.4, carbsG: 21, fatG: 0.3, fiberG: 3.6, flags: ["fiber"]),
        MealItem(name: "almonds", estimatedGrams: 20, kcal: 116, proteinG: 4.2, carbsG: 4.3, fatG: 10, fiberG: 2.5),
    ], scores: MealScores(inflammation: 80, glycemic: 76, digestion: 78))

    private static func meal(_ p: Plate, ago: Int, id: String) -> MealLog {
        let sum: (KeyPath<MealItem, Double?>) -> Double = { key in p.items.compactMap { $0[keyPath: key] }.reduce(0, +) }
        // A little day-to-day movement in the scores, so the history does not look copied.
        let nudge = Int((sin(Double(ago) * 2.3) * 5).rounded())
        return MealLog(
            id: id, loggedAt: at(-ago, p.hour, p.minute), mealType: p.type, name: p.name, source: p.photo == nil ? .text : .photo,
            analysisStatus: .complete, totalCalories: sum(\.kcal), totalProteinG: sum(\.proteinG), totalCarbsG: sum(\.carbsG),
            totalFatG: sum(\.fatG), photoPath: p.photo, totalFiberG: sum(\.fiberG), items: p.items,
            scores: MealScores(inflammation: min(96, p.scores.inflammation + nudge), glycemic: min(96, p.scores.glycemic - nudge),
                               digestion: min(96, p.scores.digestion + nudge))
        )
    }

    /// Breakfast and a snack so far today (the morning screenshots); three meals every earlier day.
    static func meals(since: Date) -> [MealLog] {
        var out: [MealLog] = [meal(snack, ago: 0, id: "showcase-meal-snack-0"), meal(breakfast, ago: 0, id: "showcase-meal-breakfast-0")]
        for ago in 1...20 {
            out.append(meal(dinner, ago: ago, id: "showcase-meal-dinner-\(ago)"))
            out.append(meal(lunch, ago: ago, id: "showcase-meal-lunch-\(ago)"))
            out.append(meal(breakfast, ago: ago, id: "showcase-meal-breakfast-\(ago)"))
        }
        return out.filter { $0.loggedAt >= since && $0.loggedAt <= now }
    }

    static func meal(id: String) -> MealLog? { meals(since: .distantPast).first { $0.id == id } }

    // MARK: Scores (the shape `member-scores` returns, so it decodes like the real thing)

    static func scores() -> MemberScores? {
        func series(_ from: Double, _ to: Double, _ phase: Double) -> String {
            (0..<14).map { i in String(curve(13 - i, from: from, to: to, wobble: 2.5, phase: phase)) }.joined(separator: ",")
        }
        let json = """
        {"day":"\(day(0))","trend":"up",
         "composite":{"score":74,"basis":"checkins_meals","pillars":{"vitality":76,"metabolic":71,"nutrition":75}},
         "vitality":{"score":76,"series14d":[\(series(66, 76, 0.4))],"tip":null,"factors":[
           {"key":"energy","label":"Energy","value":77,"weight":0.3,"status":"good","detail":null},
           {"key":"sleep","label":"Sleep","value":72,"weight":0.3,"status":"good","detail":null},
           {"key":"mood","label":"Mood","value":79,"weight":0.2,"status":"good","detail":null},
           {"key":"calm","label":"Calm","value":70,"weight":0.2,"status":"watch","detail":null}]},
         "metabolic":{"score":71,"series14d":[\(series(63, 71, 1.2))],"tip":null,"factors":[
           {"key":"glycemic","label":"Carb quality","value":74,"weight":0.5,"status":"good","detail":null},
           {"key":"rhythm","label":"Meal rhythm","value":68,"weight":0.5,"status":"watch","detail":null}]},
         "nutrition":{"score":75,"series14d":[\(series(67, 75, 2.1))],"tip":null,"factors":[
           {"key":"plants","label":"Plants & fibre","value":81,"weight":0.4,"status":"good","detail":null},
           {"key":"protein","label":"Protein","value":72,"weight":0.3,"status":"good","detail":null},
           {"key":"fat","label":"Fat quality","value":73,"weight":0.3,"status":"good","detail":null}]},
         "gut":{"score":78,"series14d":[\(series(64, 78, 0.9))],"tip":null,"factors":[]},
         "compositeSeries14d":[\(series(65, 74, 0.6))],
         "wearable":null}
        """
        // `member-scores` answers in camelCase (decoded without key conversion, like the real call).
        return try? JSONDecoder().decode(MemberScores.self, from: Data(json.utf8))
    }

    // MARK: The plan — energy, focus and sleep back, the 40–60 story (owner, 2026-10-02)

    static let objective = "Get your energy, focus and deep sleep back"

    static let cards: [String: ActionCardRow] = {
        var rhythm = ActionCardRow(id: "showcase-card-rhythm", title: "Morning circadian routine")
        rhythm.pillar = "sleep"; rhythm.cardKind = "routine"; rhythm.durationMin = 10; rhythm.defaultSlot = "morning"
        rhythm.description = "Set your body clock for the day: same wake time, daylight, water before coffee."
        rhythm.easyTitle = "Daylight at the window"; rhythm.easyDescription = "Five minutes by an open window with your first glass of water."
        rhythm.revTitle = "Walk in the morning light"; rhythm.revDescription = "Fifteen minutes outside before your first screen."
        rhythm.howMd = "1. Get up at the same time every day, weekends included.\n2. Within 30 minutes of waking, 10 minutes of outdoor daylight.\n3. A large glass of water before your first coffee.\n4. Breakfast with protein within the first two hours."
        rhythm.generalWhy = "Your body clock runs your energy, focus and sleep. A regular wake time and morning light are the strongest signals you can give it."
        rhythm.resources = [.init(kind: "youtube", query: "morning sunlight circadian rhythm routine"),
                            .init(kind: "article", slug: articleSlug, title: "Listening to your body, week by week")]
        rhythm.titleFr = "Routine circadienne du matin"
        rhythm.descriptionFr = "Réglez votre horloge interne pour la journée : même heure de lever, lumière du jour, eau avant le café."
        rhythm.easyTitleFr = "La lumière à la fenêtre"; rhythm.easyDescriptionFr = "Cinq minutes devant une fenêtre ouverte avec votre premier verre d’eau."
        rhythm.revTitleFr = "Marcher dans la lumière du matin"; rhythm.revDescriptionFr = "Quinze minutes dehors avant votre premier écran."
        rhythm.howMdFr = "1. Levez-vous à la même heure chaque jour, week-end compris.\n2. Dans les 30 minutes après le réveil, 10 minutes de lumière du jour dehors.\n3. Un grand verre d’eau avant votre premier café.\n4. Un petit-déjeuner avec des protéines dans les deux premières heures."
        rhythm.generalWhyFr = "Votre horloge interne règle votre énergie, votre concentration et votre sommeil. Une heure de lever régulière et la lumière du matin sont les signaux les plus forts que vous puissiez lui donner."
        rhythm.memberCanAdd = true
        var snack = ActionCardRow(id: "showcase-card-snack", title: "Protein snack mid-afternoon")
        snack.pillar = "nutrition"; snack.cardKind = "nutrition"; snack.durationMin = 5; snack.defaultSlot = "midday"
        snack.description = "A small protein snack around 4 pm, instead of something sweet."
        snack.howMd = "1. Greek yoghurt with a handful of nuts.\n2. Or a boiled egg and a piece of fruit.\n3. Or hummus with raw vegetables."
        snack.generalWhy = "A protein snack keeps your energy steadier through the late afternoon and takes the edge off the evening hunger."
        snack.titleFr = "Collation protéinée en milieu d’après-midi"
        snack.descriptionFr = "Une petite collation protéinée vers 16 h, à la place de quelque chose de sucré."
        snack.howMdFr = "1. Un yaourt grec avec une poignée de noix.\n2. Ou un œuf dur et un fruit.\n3. Ou du houmous avec des légumes crus."
        snack.generalWhyFr = "Une collation protéinée garde votre énergie plus stable en fin d’après-midi et calme la faim du soir."
        var strength = ActionCardRow(id: "showcase-card-strength", title: "Strength session")
        strength.pillar = "exercise"; strength.cardKind = "movement"; strength.durationMin = 25; strength.defaultSlot = "midday"
        strength.description = "Twice a week: four moves, three rounds, no equipment."
        strength.easyTitle = "Two rounds"; strength.easyDescription = "Same four moves, two rounds, longer rests."
        strength.revTitle = "Four rounds"; strength.revDescription = "Four rounds, or hold a backpack for the squats."
        strength.howMd = "1. 12 squats to a chair.\n2. 10 push-ups against a table or the floor.\n3. 12 rows with a backpack.\n4. 30-second plank.\n5. Rest one minute and repeat for three rounds."
        strength.generalWhy = "Muscle is your capacity reserve. Two short sessions a week keep you strong, steady and energetic in everyday life."
        strength.resources = [.init(kind: "youtube", query: "beginner full body strength workout no equipment 20 minutes")]
        strength.titleFr = "Séance de renforcement"
        strength.descriptionFr = "Deux fois par semaine : quatre mouvements, trois tours, sans matériel."
        strength.easyTitleFr = "Deux tours"; strength.easyDescriptionFr = "Les mêmes quatre mouvements, deux tours, avec des pauses plus longues."
        strength.revTitleFr = "Quatre tours"; strength.revDescriptionFr = "Quatre tours, ou un sac à dos chargé pour les squats."
        strength.howMdFr = "1. 12 squats jusqu’à une chaise.\n2. 10 pompes contre une table ou au sol.\n3. 12 tirages avec un sac à dos.\n4. 30 secondes de gainage.\n5. Une minute de repos, puis recommencez, trois tours en tout."
        strength.generalWhyFr = "Le muscle est votre réserve de capacité. Deux courtes séances par semaine vous gardent fort, stable et plein d’énergie au quotidien."
        var walk = ActionCardRow(id: "showcase-card-walk", title: "10-minute walk after lunch")
        walk.pillar = "exercise"; walk.cardKind = "movement"; walk.durationMin = 10; walk.defaultSlot = "midday"
        walk.description = "An easy walk straight after lunch, outside if you can."
        walk.howMd = "1. Leave within 15 minutes of finishing lunch.\n2. Walk at a pace where you can still talk.\n3. Ten minutes is enough."
        walk.generalWhy = "Moving after a meal helps your body use what you just ate, and it is the best antidote to the afternoon dip."
        walk.titleFr = "Marche de 10 minutes après le déjeuner"
        walk.descriptionFr = "Une marche tranquille juste après le déjeuner, dehors si possible."
        walk.howMdFr = "1. Partez dans les 15 minutes qui suivent la fin du repas.\n2. Marchez à un rythme où vous pouvez encore parler.\n3. Dix minutes suffisent."
        walk.generalWhyFr = "Bouger après un repas aide votre corps à utiliser ce que vous venez de manger, et c’est le meilleur remède au coup de mou de l’après-midi."
        walk.memberCanAdd = true
        // The breathing card: the only kind with its own pacer — shown from the bank, as a member discovers it.
        var breath = ActionCardRow(id: breathCardId, title: "Slow breathing before bed")
        breath.pillar = "sleep"; breath.cardKind = "breath"; breath.durationMin = 5; breath.defaultSlot = "evening"
        breath.description = "Five minutes of slow, even breathing in bed, eyes closed."
        breath.easyTitle = "Ten slow breaths"; breath.easyDescription = "Just ten breaths with the circle, then let go."
        breath.howMd = "1. Lie on your back, one hand on your belly.\n2. Breathe in gently through your nose as the circle grows.\n3. Breathe out slowly as it shrinks.\n4. If your mind wanders, come back to the circle."
        breath.generalWhy = "A slow, even breathing rhythm is a simple way to let the day go before sleep."
        breath.resources = [.init(kind: "youtube", query: "slow breathing exercise before sleep 5 minutes")]
        breath.titleFr = "Respiration lente avant le coucher"
        breath.descriptionFr = "Cinq minutes de respiration lente et régulière au lit, les yeux fermés."
        breath.easyTitleFr = "Dix respirations lentes"; breath.easyDescriptionFr = "Seulement dix respirations avec le cercle, puis laissez aller."
        breath.howMdFr = "1. Allongez-vous sur le dos, une main sur le ventre.\n2. Inspirez doucement par le nez pendant que le cercle grandit.\n3. Expirez lentement pendant qu’il rétrécit.\n4. Si votre esprit s’évade, revenez au cercle."
        breath.generalWhyFr = "Un rythme de respiration lent et régulier est une façon simple de laisser partir la journée avant de dormir."
        breath.memberCanAdd = true
        return [rhythm.id: rhythm, snack.id: snack, strength.id: strength, walk.id: walk, breath.id: breath]
    }()

    private static func habit(_ id: String, _ title: String, slot: String?, card: String, pillar: String, rule: String = "FREQ=DAILY") -> HabitRow {
        HabitRow(id: id, carePlanItemId: "item-\(id)", title: title, description: nil, frequencyRule: rule, status: "active",
                 source: "prescribed", pillar: pillar, slot: slot, appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                 revTitle: nil, revDescription: nil, createdAt: ISO8601.string(at(-24, 10)), habitBankId: card)
    }

    /// Twice a week, today one of the two days (so the session shows in today's actions).
    private static func twiceAWeek(including today: String) -> String {
        let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        let dow = HabitEngine.weekday(today) ?? 2
        return "FREQ=WEEKLY;BYDAY=\(codes[dow]),\(codes[(dow + 3) % 7])"
    }

    static func habitPlan(day today: String) -> HabitPlan {
        // A prescription's title is written in the member's language (it wins over the card's title in the app).
        let fr = TodayFocus.locale() == "fr"
        let habits = [
            habit("showcase-h-rhythm", fr ? "Routine circadienne du matin" : "Morning circadian routine", slot: "morning",
                  card: "showcase-card-rhythm", pillar: "sleep"),
            habit(actionHabitId, fr ? "Séance de renforcement · deux fois par semaine" : "Strength session · twice a week", slot: "midday",
                  card: "showcase-card-strength", pillar: "exercise", rule: twiceAWeek(including: today)),
            habit("showcase-h-walk", fr ? "Marche de 10 minutes après le déjeuner" : "10-minute walk after lunch", slot: "midday",
                  card: "showcase-card-walk", pillar: "exercise"),
            habit("showcase-h-snack", fr ? "Collation protéinée en milieu d’après-midi" : "Protein snack mid-afternoon", slot: "midday",
                  card: "showcase-card-snack", pillar: "nutrition"),
        ]
        var completions: [HabitCompletionRow] = []
        for ago in 1...20 {
            for (i, h) in habits.enumerated() where (ago + i) % 5 != 0
                && HabitEngine.isDue(h.frequencyRule, on: day(-ago), start: nil) {   // most due days, not every one
                completions.append(HabitCompletionRow(id: "c-\(h.id)-\(ago)", habitId: h.id, completionDate: day(-ago)))
            }
        }
        completions.append(HabitCompletionRow(id: "c-rhythm-today", habitId: "showcase-h-rhythm", completionDate: today))
        var plan = HabitPlan(
            day: today,
            header: HabitPlanHeader(id: "showcase-plan", title: "Care plan", startDate: day(-24), objectiveLine: objective),
            phases: [
                HabitPlanPhase(phaseKey: "p1", weekStart: 1, weekEnd: 2, title: "Reset your circadian rhythm", summary: nil),
                HabitPlanPhase(phaseKey: "p2", weekStart: 3, weekEnd: 6, title: "Build the foundations of functional capacity",
                               summary: "With your body clock steadier, we build capacity: protein at every meal, strength training twice a week and movement after meals."),
                HabitPlanPhase(phaseKey: "p3", weekStart: 7, weekEnd: 10, title: "Improve metabolic flexibility", summary: nil),
            ],
            habits: habits, completions: completions
        )
        plan.goals = [
            "Steady energy from morning to evening, without the 3 pm crash",
            "Ninety minutes of sharp focus when you need it",
            "Sleep through the night and wake up rested five days out of seven",
            "Feel strong and capable in everyday life again",
        ]
        plan.priorities = ["Morning light", "Protein at every meal", "Strength twice a week", "Move after meals"]
        plan.cards = cards
        return plan
    }

    static let carePlan = CarePlan(
        title: "Care plan", startDate: "", practitioner: "",
        goals: ["Steady energy from morning to evening", "Sleep through the night"],
        sections: [
            CarePlan.Section(category: "Rhythm & sleep", symbol: "sun.max", colorHex: 0xC9962E, items: [
                CarePlan.Item(id: "s1", text: "Same wake time every day, daylight within 30 minutes", status: .active),
                CarePlan.Item(id: "s2", text: "Screens off 30 minutes before bed, bedroom cool and dark", status: .active),
            ]),
            CarePlan.Section(category: "Nutrition", symbol: "leaf", colorHex: 0x4A8A5C, items: [
                CarePlan.Item(id: "s3", text: "Protein at every meal, a palm-sized portion", status: .active),
                CarePlan.Item(id: "s4", text: "A protein snack mid-afternoon instead of something sweet", status: .active),
                CarePlan.Item(id: "s5", text: "Coffee before noon only", status: .completed),
            ]),
            CarePlan.Section(category: "Movement", symbol: "figure.strengthtraining.traditional", colorHex: 0xC07A3B, items: [
                CarePlan.Item(id: "s6", text: "Strength training twice a week", status: .active),
                CarePlan.Item(id: "s7", text: "A 10-minute walk after lunch", status: .active),
            ]),
            CarePlan.Section(category: "Focus", symbol: "brain.head.profile", colorHex: 0x5B6FA8, items: [
                CarePlan.Item(id: "s8", text: "Work in 90-minute blocks with a 5-minute break outside", status: .active),
            ]),
        ]
    )

    // MARK: Library (real topic covers — public practice content, not member data)

    static let coverBase = "https://ndojytvvlvlbgtodujkf.supabase.co/storage/v1/object/public/content-public/library/covers/"
    static let covers: [LibraryTopicCoverRow] = ["energie", "foundations", "hormones", "inflammation", "intestin", "mouvement", "nutrition", "sommeil", "stress"]
        .map { LibraryTopicCoverRow(topic: $0, imageUrl: coverBase + "\($0)-20260930T100753Z.webp") }

    static func libraryRaw() -> LibraryRaw {
        var raw = LibraryRaw()
        let demo = LibraryDemo.tracks
        raw.tracks = demo.enumerated().map { i, t in
            LibraryRawTrack(id: "showcase-track-\(i)", slug: String(t.slug.dropFirst(5)), title: t.title, description: t.description, pillar: t.pillar,
                            coverStyle: nil, position: i + 1, requiresStage: nil, requiresTrackId: nil)
        }
        for (i, t) in demo.enumerated() {
            for lesson in t.lessons {
                let slug = "showcase-\(lesson.contentSlug.dropFirst(5))"
                raw.lessons.append(LibraryRawLesson(trackId: "showcase-track-\(i)", position: lesson.position, contentSlug: slug))
                raw.list.append(LibraryListRow(slug: slug, title: lesson.title, summary: nil, publishedAt: nil, tags: [t.pillar ?? "foundations"], isLocked: false, coverUrl: nil))
                if lesson.done { raw.progress.append(LibraryRawProgress(trackId: "showcase-track-\(i)", contentSlug: slug)) }
            }
        }
        raw.list.append(LibraryListRow(slug: articleSlug, title: "Listening to your body, week by week", summary: "The weekly loop: act, notice, adjust.",
                                       publishedAt: nil, tags: ["intestin"], isLocked: false, coverUrl: nil))
        for r in LibraryDemo.resources {
            raw.list.append(LibraryListRow(slug: "showcase-\(r.slug.dropFirst(5))", title: r.title, summary: r.summary, publishedAt: nil,
                                           tags: [r.supplement ? "supplement" : (r.pillar ?? "foundations")], isLocked: false, coverUrl: nil))
        }
        raw.access = .open
        raw.priorityTrackIds = ["showcase-track-0"]
        raw.plan = LibraryRawPlan(id: "showcase-plan", title: objective, startDate: day(-24))
        raw.planObjectives = ["Steady energy from morning to evening"]
        return raw
    }

    static func libraryItem(slug: String) -> LibraryGetRow? {
        let title = libraryRaw().list.first { $0.slug == slug }?.title ?? "Listening to your body, week by week"
        return LibraryGetRow(title: title, tags: ["intestin"], bodyMd: LibraryDemo.readerBody, locked: false)
    }
}
#endif
