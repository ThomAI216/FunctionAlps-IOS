#if DEBUG
import Foundation

/// Today's focus for the screenshots (owner, 2026-11-12): Home's card on P1 (borrowed energy), P5 (low battery, with the practitioner
/// line) and G1 (ride the good night), the habit-choice sheet, an action opened from it, the kickoff morning routine and the evening
/// follow-up. The server's answer, as sample JSON (the same shape `member-daily-focus` returns, decoded the same way): the words are the
/// matrix's, and the habits are real `habit_bank` cards (their real ids and titles). Nothing here is a real person.
enum ShowcaseFocus {
    static var isOn: Bool {
        switch Showcase.screen {
        case .focusP1, .focusP5, .focusG1, .focusSheet, .focusAction, .focusKickoff, .focusKickoffDone, .focusEvening, .focusPageP1, .focusPageP5, .focusHome, .focusHomeDone: true
        default: false
        }
    }

    /// Home with the green "Kickoff morning routine" row (owner, 2026-11-13).
    static var homeIsOn: Bool { Showcase.screen == .focusHome || Showcase.screen == .focusHomeDone }

    /// The phone's clock for the routine card: Home's During the day list is the midday routine, so those two shots read 12:00 (the
    /// others keep the real clock, as every screenshot does).
    static func clock() -> @Sendable () -> Date {
        guard homeIsOn else { return { Date() } }
        return { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date() }
    }

    /// The cell each screen shows; every screen but P1 and G1 is a hard morning (P5).
    static var cellId: String {
        switch Showcase.screen {
        case .focusP1, .focusPageP1: "P1"
        case .focusG1: "G1"
        default: "P5"
        }
    }

    /// The card the "Do it now" action opens.
    static let actionCardId = "fd592c9e-34d9-4a8c-b548-e7b6605aab04"

    private static var fr: Bool { TodayFocus.locale() == "fr" }

    private struct Habit { let id: String; let en: String; let fr: String?; let detailEn: String; let detailFr: String? }

    private static let habits: [String: Habit] = [
        "daylight": Habit(id: "afa499c9-5033-43d3-bf0c-81f2b8e70819", en: "Open the window, two minutes counts", fr: nil,
                          detailEn: "Right when you wake up: daylight and fresh air, before your phone.", detailFr: nil),
        "coffee": Habit(id: "09934b99-c538-4afb-80fb-c3606e58a7c7", en: "First coffee 60 to 90 minutes after waking", fr: "Le premier café 60 à 90 minutes après le lever",
                        detailEn: "Wait 60 minutes after waking before your first coffee or tea, and up to 90 if it suits you.",
                        detailFr: "Attendez 60 minutes après le réveil avant votre premier café ou thé, et jusqu’à 90 si cela vous convient."),
        "screens": Habit(id: "47613f35-cb86-4122-b168-ea3135a7a208", en: "Screens off 60 minutes before bed", fr: "Écrans éteints 60 minutes avant le coucher",
                         detailEn: "A full hour without screens before you sleep.", detailFr: "Une heure entière sans écrans avant de dormir."),
        "water": Habit(id: "fd592c9e-34d9-4a8c-b548-e7b6605aab04", en: "A glass of water before coffee", fr: "Un verre d’eau avant le café",
                       detailEn: "Start hydrated and the coffee lands softer.", detailFr: "Commencez par vous hydrater et le café passe plus en douceur."),
        "protein": Habit(id: "8ba3035e-a61f-4458-b078-9918624b8b18", en: "Anything at breakfast counts", fr: "Des protéines au petit-déjeuner",
                         detailEn: "Eggs, skyr, leftovers: anything. Steadier energy before 11:00.", detailFr: "Œufs, skyr, restes : peu importe. Une énergie plus stable jusqu’à 11 h."),
        "move": Habit(id: "623658e7-bea0-41a9-9fe5-d646a3340dda", en: "Morning activation, five minutes", fr: "Activation matinale, cinq minutes",
                      detailEn: "Wake the body before the day claims it.", detailFr: "Réveillez le corps avant que la journée ne s’en empare."),
        "further": Habit(id: "eb7923e5-def2-4243-a265-1d9d8c4c4634", en: "Make the walk 20 minutes", fr: nil,
                         detailEn: "Your five-minute activation, then a 10-minute walk outside.", detailFr: nil),
        "breath": Habit(id: "3779f8d5-2b4c-4a1d-9182-b9e0a9785176", en: "5 minutes of breathing, once a day", fr: nil,
                        detailEn: "5 minutes for yourself, once a day: deep breaths, a slow exhale, a hold.", detailFr: nil),
        "connect": Habit(id: "21bdbd09-0448-4d1d-b9e3-9c8652fb0fb0", en: "Reach out to someone you care about", fr: nil,
                         detailEn: "A message or a call to someone you care about.", detailFr: nil),
    ]

    private static func text(_ h: Habit) -> (title: String, detail: String) {
        // One language per habit, like the server: French only when everything it has is written in French.
        if fr, let title = h.fr, let detail = h.detailFr { return (title, detail) }
        return (h.en, h.detailEn)
    }

    private static func offerJSON(_ key: String, rank: Int, variant: String = "standard") -> String {
        guard let h = habits[key] else { return "" }
        let t = text(h)
        return """
        {"id":"o\(rank)","offerKey":"bank:\(h.id)","cardId":"\(h.id)","rank":\(rank),"title":\(quoted(t.title)),"description":\(quoted(t.detail)),
         "pillar":null,"slot":"morning","variant":"\(variant)","reason":"focus","trigger":"\(cellId)","stateTitle":null,"accepted":null,"completed":false}
        """
    }

    private static func quoted(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let out = String(data: data, encoding: .utf8) else { return "\"\"" }
        return out
    }

    private struct CellText { let headlineEn: String; let lineEn: String; let headlineFr: String; let lineFr: String; let tone: String; let offers: [(String, String)] }

    private static func cellText() -> CellText {
        switch cellId {
        case "P1":
            CellText(headlineEn: "Good energy on a short night",
                     lineEn: "Go with the flow, and leave yourself some slack: daylight now, an easy lunch, a calmer evening.",
                     headlineFr: "De l’énergie malgré une nuit courte",
                     lineFr: "Suivez votre élan, mais gardez un peu de marge : de la lumière dès maintenant, un déjeuner léger, une soirée plus calme.",
                     tone: "go", offers: [("daylight", "easy"), ("coffee", "standard"), ("screens", "standard")])
        case "G1":
            CellText(headlineEn: "You’re set for a great day",
                     lineEn: "A good night and good energy: this is the day for a step further.",
                     headlineFr: "Vous êtes prêt pour une belle journée",
                     lineFr: "Une bonne nuit et une bonne énergie : c’est le jour d’aller un cran plus loin.",
                     tone: "peak", offers: [("move", "standard"), ("further", "progression")])
        default:
            CellText(headlineEn: "Today is for holding steady",
                     lineEn: "Keep one priority, lighten the rest, and rest when you can. Water and a proper breakfast first.",
                     headlineFr: "Aujourd’hui, on tient le cap",
                     lineFr: "Gardez une seule priorité, allégez le reste et reposez-vous dès que possible. De l’eau et un vrai petit-déjeuner d’abord.",
                     tone: "rest", offers: [("water", "standard"), ("protein", "easy"), ("connect", "easy")])
        }
    }

    private static func kickoffJSON() -> String {
        let order: [(String, String, String, String)] = [
            ("move", "movement", "Movement", "Mouvement"), ("breath", "breathing", "Breathing", "Respiration"),
            ("daylight", "light", "Daylight", "Lumière du jour"), ("connect", "connection", "Connection & positivity", "Lien et positivité"),
            ("water", "hydration", "Hydration", "Hydratation"), ("protein", "protein", "High-protein breakfast", "Petit-déjeuner riche en protéines"),
        ]
        let steps = order.compactMap { key, kind, labelEn, labelFr -> String? in
            guard let h = habits[key] else { return nil }
            let t = text(h)
            return #"{"kind":"\#(kind)","label":\#(quoted(fr ? labelFr : labelEn)),"cardId":"\#(h.id)","title":\#(quoted(t.title)),"description":\#(quoted(t.detail))}"#
        }.joined(separator: ",")
        let title = fr ? "Routine de démarrage du matin" : "Kickoff morning routine"
        let subtitle = fr ? "De petites étapes pour un matin lent, dans cet ordre. Cochez chacune pour continuer."
                          : "Small steps for a slow morning, in this order. Tick each one to go on."
        let finishTitle = fr ? "Votre matinée est lancée" : "Your morning has started"
        let finishLine = fr ? "Le démarrage est fait. Prenez le reste de la journée à votre rythme." : "That is the kickoff done. Take the rest of the day at your own pace."
        return #"{"key":"kickoff_morning","title":\#(quoted(title)),"subtitle":\#(quoted(subtitle)),"finishTitle":\#(quoted(finishTitle)),"finishLine":\#(quoted(finishLine)),"steps":[\#(steps)]}"#
    }

    /// The server's reply for this screen's cell, decoded like the real one.
    static func focus() -> TodayFocus {
        let c = cellText()
        let hard = cellId != "G1"
        let kickoff = cellId == "G1" ? "null" : kickoffJSON()
        let practitioner = cellId == "P5"
            ? quoted(fr ? "Nous en parlerons ensemble avec votre praticien." : "We’ll look at it together with your practitioner.")
            : "null"
        let offers = c.offers.enumerated().map { offerJSON($0.element.0, rank: $0.offset + 1, variant: $0.element.1) }.joined(separator: ",")
        let json = """
        {"day":"\(ShowcaseData.day(0))","needsCheckin":false,"offers":[\(offers)],"readiness":{"band":"low","vsBaseline":false,"source":"self_report"},
         "cell":{"id":"\(cellId)","headline":\(quoted(fr ? c.headlineFr : c.headlineEn)),"line":\(quoted(fr ? c.lineFr : c.lineEn)),"tone":"\(c.tone)",
                 "practitionerLine":\(practitioner),"hardMorning":\(hard),"kickoff":\(kickoff)}}
        """
        return (try? JSON.decode(TodayFocus.self, from: Data(json.utf8))) ?? TodayFocus(day: ShowcaseData.day(0), needsCheckin: false, offers: [])
    }

    /// The real cards behind the habits, as members may add them (bank).
    static var cards: [ActionCardRow] {
        habits.values.map { h -> ActionCardRow in
            var card = ActionCardRow(id: h.id, title: h.en)
            card.description = h.detailEn
            card.titleFr = h.fr
            card.descriptionFr = h.detailFr
            card.pillar = h.id == actionCardId ? "nutrition" : nil
            card.defaultSlot = "morning"
            card.memberCanAdd = true
            return card
        }
    }

    /// What the evening follow-up shows already answered: better, thanks to this morning's routine and people.
    static let evening = EveningFollowup(choice: .better, pills: [EveningFollowupLogic.kickoffKey, EveningFollowupLogic.habitKey(habits["water"]?.id ?? "water"),
                                                                    EveningFollowupLogic.habitKey("showcase-card-rhythm")])
}
#endif
