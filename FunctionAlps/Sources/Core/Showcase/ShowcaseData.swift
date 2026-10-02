#if DEBUG
import Foundation

/// The sample member the showcase screenshots show. Invented end to end: "Marie" (a first name only), three weeks
/// of check-ins drifting gently upward, ordinary meals, and a plan written by Alessandra. Every day is relative to
/// today, so the screenshots always look current.
enum ShowcaseData {
    static let patientId = "showcase-marie"
    static let userId = "showcase-user"
    static let heroMealId = "showcase-meal-lunch-1"
    static let breathHabitId = "showcase-h-breath"
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
            sex: .female, age: 38, heightCm: 168, weightKg: 63, activityLevel: "moderate",
            healthGoals: ["energy", "digestion", "sleep"], currentComplaints: ["afternoon slump", "bloating"],
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
        m.energyBody = 74; m.energyMind = 78; m.energyStability = 70; m.energyOverall = 76
        m.moodScore = 80; m.stressScore = 30
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

    // MARK: The plan, with Alessandra

    static let cards: [String: ActionCardRow] = {
        var breath = ActionCardRow(id: "showcase-card-breath", title: "4-7-8 breathing")
        breath.pillar = "sleep"; breath.cardKind = "breath"; breath.durationMin = 5; breath.defaultSlot = "evening"
        breath.description = "A slow breath to tell your body the day is over."
        breath.easyTitle = "Three slow breaths"; breath.easyDescription = "Just three rounds, sitting on the edge of the bed."
        breath.revTitle = "Eight rounds"; breath.revDescription = "Eight full rounds, then stay still for a minute."
        breath.howMd = "1. Sit comfortably, one hand on your belly.\n2. Breathe in through your nose for 4.\n3. Hold for 7.\n4. Breathe out slowly through your mouth for 8.\n5. Repeat four times."
        breath.generalWhy = "A longer out-breath is one of the simplest ways to slow down before sleep. Alessandra added it while we work on your evenings."
        breath.resources = [.init(kind: "youtube", query: "4-7-8 breathing guided"), .init(kind: "article", slug: articleSlug, title: "Listening to your gut, week by week")]
        var walk = ActionCardRow(id: "showcase-card-walk", title: "10-minute walk after lunch")
        walk.pillar = "exercise"; walk.cardKind = "movement"; walk.durationMin = 10; walk.defaultSlot = "midday"
        walk.description = "An easy walk straight after lunch."
        walk.howMd = "1. Leave your desk within 15 minutes of finishing lunch.\n2. Walk at a pace where you can still talk.\n3. Ten minutes is enough."
        walk.generalWhy = "Moving after a meal helps your body use what you just ate, and it is a good antidote to the afternoon slump."
        var water = ActionCardRow(id: "showcase-card-water", title: "A glass of water before coffee")
        water.pillar = "nutrition"; water.cardKind = "routine"; water.durationMin = 1; water.defaultSlot = "morning"
        water.howMd = "1. Keep a glass by the kettle.\n2. Drink it before your first coffee."
        var plate = ActionCardRow(id: "showcase-card-plants", title: "Two plants at lunch")
        plate.pillar = "nutrition"; plate.cardKind = "nutrition"; plate.defaultSlot = "midday"
        plate.howMd = "1. Add two different vegetables or legumes to your lunch.\n2. Colour counts: pick two you did not have yesterday."
        return [breath.id: breath, walk.id: walk, water.id: water, plate.id: plate]
    }()

    private static func habit(_ id: String, _ title: String, slot: String?, card: String, pillar: String) -> HabitRow {
        HabitRow(id: id, carePlanItemId: "item-\(id)", title: title, description: nil, frequencyRule: "FREQ=DAILY", status: "active",
                 source: "prescribed", pillar: pillar, slot: slot, appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                 revTitle: nil, revDescription: nil, createdAt: ISO8601.string(at(-24, 10)), habitBankId: card)
    }

    static func habitPlan(day today: String) -> HabitPlan {
        let habits = [
            habit("showcase-h-water", "A glass of water before coffee", slot: "morning", card: "showcase-card-water", pillar: "nutrition"),
            habit("showcase-h-plants", "Two plants at lunch", slot: "midday", card: "showcase-card-plants", pillar: "nutrition"),
            habit("showcase-h-walk", "10-minute walk after lunch", slot: "midday", card: "showcase-card-walk", pillar: "exercise"),
            habit(breathHabitId, "4-7-8 breathing before bed", slot: "evening", card: "showcase-card-breath", pillar: "sleep"),
        ]
        var completions: [HabitCompletionRow] = []
        for ago in 1...20 {
            for (i, h) in habits.enumerated() where (ago + i) % 5 != 0 {   // most days, not every day
                completions.append(HabitCompletionRow(id: "c-\(h.id)-\(ago)", habitId: h.id, completionDate: day(-ago)))
            }
        }
        completions.append(HabitCompletionRow(id: "c-water-today", habitId: "showcase-h-water", completionDate: today))
        var plan = HabitPlan(
            day: today,
            header: HabitPlanHeader(id: "showcase-plan", title: "Care plan", startDate: day(-24), objectiveLine: "Steady energy through the afternoon"),
            phases: [
                HabitPlanPhase(phaseKey: "p1", weekStart: 1, weekEnd: 2, title: "Settle", summary: nil),
                HabitPlanPhase(phaseKey: "p2", weekStart: 3, weekEnd: 6, title: "Rebuild", summary: "We steady your meals and evenings first: regular lunches, a calmer wind-down, and a walk to carry you through the afternoon."),
                HabitPlanPhase(phaseKey: "p3", weekStart: 7, weekEnd: 10, title: "Consolidate", summary: nil),
            ],
            habits: habits, completions: completions
        )
        plan.goals = ["No more afternoon slump", "Less bloating after meals", "Waking up rested five days out of seven"]
        plan.priorities = ["Regular lunches", "A calmer evening", "Balance the microbiome"]
        plan.cards = cards
        return plan
    }

    static let carePlan = CarePlan(
        title: "Care plan", startDate: "September 2026", practitioner: "With Alessandra",
        goals: ["No more afternoon slump", "Less bloating after meals"],
        sections: [
            CarePlan.Section(category: "Nutrition", symbol: "leaf", colorHex: 0x4A8A5C, items: [
                CarePlan.Item(id: "s1", text: "Lunch between 12:00 and 13:00, with protein and two plants", status: .active),
                CarePlan.Item(id: "s2", text: "Swap the afternoon biscuit for fruit and a handful of nuts", status: .completed),
            ]),
            CarePlan.Section(category: "Sleep", symbol: "moon", colorHex: 0x5B6FA8, items: [
                CarePlan.Item(id: "s3", text: "Screens off 30 minutes before bed", status: .active),
            ]),
            CarePlan.Section(category: "Movement", symbol: "figure.walk", colorHex: 0xC07A3B, items: [
                CarePlan.Item(id: "s4", text: "A walk after lunch on working days", status: .active),
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
        raw.list.append(LibraryListRow(slug: articleSlug, title: "Listening to your gut, week by week", summary: "The weekly loop: act, notice, adjust.",
                                       publishedAt: nil, tags: ["intestin"], isLocked: false, coverUrl: nil))
        for r in LibraryDemo.resources {
            raw.list.append(LibraryListRow(slug: "showcase-\(r.slug.dropFirst(5))", title: r.title, summary: r.summary, publishedAt: nil,
                                           tags: [r.supplement ? "supplement" : (r.pillar ?? "foundations")], isLocked: false, coverUrl: nil))
        }
        raw.access = .open
        raw.priorityTrackIds = ["showcase-track-0"]
        raw.plan = LibraryRawPlan(id: "showcase-plan", title: "Steady energy through the afternoon", startDate: day(-24))
        raw.planObjectives = ["No more afternoon slump"]
        return raw
    }

    static func libraryItem(slug: String) -> LibraryGetRow? {
        let title = libraryRaw().list.first { $0.slug == slug }?.title ?? "Listening to your gut, week by week"
        return LibraryGetRow(title: title, tags: ["intestin"], bodyMd: LibraryDemo.readerBody, locked: false)
    }
}
#endif
