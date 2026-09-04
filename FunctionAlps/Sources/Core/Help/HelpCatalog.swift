import Foundation

/// The single source of every patient-facing explanation (the Expo `lib/help/help-content.ts`).
/// Voice rules: never call what the member types "data"; felt before measured; nothing diagnoses.
struct HelpEntry: Sendable, Equatable, Identifiable {
    enum Group: String, CaseIterable, Sendable { case start, around, checkins, food }
    struct Point: Sendable, Equatable { let label: String; let text: String }

    let key: String
    let group: Group
    let title: String
    let lede: String
    let body: String
    let points: [Point]
    var footnote: String? = nil
    /// The tab the "Open this screen" button switches to; nil for hub-only chapters.
    var opens: AppRouter.Tab? = nil
    var id: String { key }
}

struct HelpGroup: Sendable, Equatable, Identifiable {
    let key: HelpEntry.Group
    let title: String
    let blurb: String
    let entries: [HelpEntry]
    var id: String { key.rawValue }
}

enum HelpCatalog {
    static let heroKey = "overview"

    static var groups: [HelpGroup] {
        let defs: [(HelpEntry.Group, String, String)] = [
            (.start, String(localized: "help.group.start", defaultValue: "Start here"), String(localized: "help.group.start.blurb", defaultValue: "What this app is, and why the small stuff matters.")),
            (.around, String(localized: "help.group.around", defaultValue: "Around the app"), String(localized: "help.group.around.blurb", defaultValue: "Home, Trends, Food and Library · what each one is for.")),
            (.checkins, String(localized: "help.group.checkins", defaultValue: "Your daily check-ins"), String(localized: "help.group.checkins.blurb", defaultValue: "The two-minute habit everything else is built on.")),
            (.food, String(localized: "help.group.food", defaultValue: "Logging your food"), String(localized: "help.group.food.blurb", defaultValue: "Photo to plate to pattern.")),
        ]
        let all = entries
        return defs.map { def in HelpGroup(key: def.0, title: def.1, blurb: def.2, entries: all.filter { $0.group == def.0 }) }
            .filter { !$0.entries.isEmpty }
    }

    static func entry(_ key: String) -> HelpEntry? { entries.first { $0.key == key } }

    static var entries: [HelpEntry] {
        [
            HelpEntry(
                key: "overview", group: .start,
                title: String(localized: "help.overview.title", defaultValue: "What this app is for"),
                lede: String(localized: "help.overview.lede", defaultValue: "the short version"),
                body: String(localized: "help.overview.body", defaultValue: "This is where your everyday life and your practitioner’s work meet. You log a few simple things · how you feel, and what you ate. The app turns that into a picture the two of you can look at together, so your appointments start from what actually happened rather than from what you can remember."),
                points: [
                    .init(label: String(localized: "help.overview.p1.label", defaultValue: "What you do"), text: String(localized: "help.overview.p1.text", defaultValue: "A thirty-second check-in most days, and a photo of your meals when you can manage it.")),
                    .init(label: String(localized: "help.overview.p2.label", defaultValue: "What you get back"), text: String(localized: "help.overview.p2.text", defaultValue: "Scores that show which way things are heading, and short reports that pull a week together.")),
                    .init(label: String(localized: "help.overview.p3.label", defaultValue: "What your practitioner sees"), text: String(localized: "help.overview.p3.text", defaultValue: "The same picture you do · so they arrive at your call already up to speed.")),
                    .init(label: String(localized: "help.overview.p4.label", defaultValue: "What it is not"), text: String(localized: "help.overview.p4.text", defaultValue: "It does not diagnose anything, and it does not replace your practitioner. It is the record you build between visits.")),
                ],
                footnote: String(localized: "help.overview.footnote", defaultValue: "If something about your health worries you, message your practitioner rather than waiting for a number to change.")
            ),
            HelpEntry(
                key: "why-you-log", group: .start,
                title: String(localized: "help.why.title", defaultValue: "Why the small stuff you type matters"),
                lede: String(localized: "help.why.lede", defaultValue: "thirty seconds a day, and what it buys you"),
                body: String(localized: "help.why.body", defaultValue: "It is the least impressive-looking part of the app, and it is the part that makes everything else about you. On day one the app only knows what was on your intake form · it can be helpful, but it is being helpful in general. After two weeks of check-ins and meals it knows your afternoons dip, that bread sits badly with you, that you sleep better on days you walk. Now it is being helpful about you."),
                points: [
                    .init(label: String(localized: "help.why.p1.label", defaultValue: "Nothing is wasted"), text: String(localized: "help.why.p1.text", defaultValue: "Every check-in, every meal, every \"that one felt rough\" makes the next thing you see sharper.")),
                    .init(label: String(localized: "help.why.p2.label", defaultValue: "An off day helps too"), text: String(localized: "help.why.p2.text", defaultValue: "A rough week is not a hole in your record. It is often the most useful week in it.")),
                    .init(label: String(localized: "help.why.p3.label", defaultValue: "Your practitioner reads it"), text: String(localized: "help.why.p3.text", defaultValue: "They come to your call already knowing how your month went, so you can spend the call on what to do next.")),
                    .init(label: String(localized: "help.why.p4.label", defaultValue: "You are allowed to be quick"), text: String(localized: "help.why.p4.text", defaultValue: "Rough and honest beats precise and skipped. A slider roughly in the right place is plenty.")),
                ],
                footnote: String(localized: "help.why.footnote", defaultValue: "The more of your ordinary days it sees, the more the advice fits your life rather than an average one.")
            ),
            HelpEntry(
                key: "felt-vs-measured", group: .start,
                title: String(localized: "help.felt.title", defaultValue: "Your body keeps a record your bloods don’t"),
                lede: String(localized: "help.felt.lede", defaultValue: "why we ask how you feel, not just what your watch says"),
                body: String(localized: "help.felt.body", defaultValue: "A blood test tells you where you were on one particular morning. A watch tells you what your body did while you slept. Both are useful. Neither one knows how you actually felt on Tuesday · and that is usually the thing that tells you whether something is working."),
                points: [
                    .init(label: String(localized: "help.felt.p1.label", defaultValue: "How you feel is real information"), text: String(localized: "help.felt.p1.text", defaultValue: "Energy, digestion, mood, sleep. You are the only one who can report these, and they shift long before a lab marker does.")),
                    .init(label: String(localized: "help.felt.p2.label", defaultValue: "The point is noticing the link"), text: String(localized: "help.felt.p2.text", defaultValue: "Late dinner, rough sleep. Skipped the walk, flat afternoon. The app lines these up so the pattern shows itself.")),
                    .init(label: String(localized: "help.felt.p3.label", defaultValue: "Together they beat either alone"), text: String(localized: "help.felt.p3.text", defaultValue: "When your watch says you slept fine and you felt wrecked, that gap is the interesting part. It is not an error.")),
                ],
                footnote: String(localized: "help.felt.footnote", defaultValue: "This is why your own check-ins carry more weight in your scores than any device does.")
            ),
            HelpEntry(
                key: "home", group: .around,
                title: String(localized: "help.home.title", defaultValue: "Home"),
                lede: String(localized: "help.home.lede", defaultValue: "your day, at a glance"),
                body: String(localized: "help.home.body", defaultValue: "The first thing you see. It is a summary rather than a to-do list · the big number tells you roughly where you are, and everything under it is a shortcut to whatever you would want next."),
                points: [
                    .init(label: String(localized: "help.point.whatToDo", defaultValue: "What to do"), text: String(localized: "help.home.p1.text", defaultValue: "Tick today’s actions as you go · they build your day’s picture too.")),
                    .init(label: String(localized: "help.point.whatYouSee", defaultValue: "What you’re seeing"), text: String(localized: "help.home.p2.text", defaultValue: "The small daily things you and your practitioner agreed on, and the score they feed.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.home.p3.text", defaultValue: "Doing beats reading · today’s two or three actions come before any number.")),
                ],
                footnote: String(localized: "help.home.footnote", defaultValue: "Dashes just mean nothing is logged yet. It fills in as you go."),
                opens: .home
            ),
            HelpEntry(
                key: "trends", group: .around,
                title: String(localized: "help.trends.title", defaultValue: "Trends"),
                lede: String(localized: "help.trends.lede", defaultValue: "your progress, in one number"),
                body: String(localized: "help.trends.body", defaultValue: "Everything you log · your check-ins, your meals · rolls up into one score. It is here so you can see whether things are moving in the right direction without having to read charts."),
                points: [
                    .init(label: String(localized: "help.point.whatToDo", defaultValue: "What to do"), text: String(localized: "help.trends.p1.text", defaultValue: "Tap any of the three parts to see exactly what moved it.")),
                    .init(label: String(localized: "help.point.whatWeLookAt", defaultValue: "What we look at"), text: String(localized: "help.trends.p2.text", defaultValue: "Everything you log, rolled into one score · your own check-ins first, your device second.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.trends.p3.text", defaultValue: "You see direction, not noise. A low day is information, not a failure · and your practitioner sees this same view.")),
                ],
                opens: .trends
            ),
            HelpEntry(
                key: "food", group: .around,
                title: String(localized: "help.food.title", defaultValue: "Reading your plate"),
                lede: String(localized: "help.food.lede", defaultValue: "what a finished read looks like"),
                body: String(localized: "help.food.body", defaultValue: "Log a meal here and the app works out roughly what was in it. You do not need to weigh anything or look up numbers · a photo is enough, and you can correct it afterwards."),
                points: [
                    .init(label: String(localized: "help.point.whatWeLookAt", defaultValue: "What we look at"), text: String(localized: "help.food.p1.text", defaultValue: "The foods on your plate and roughly how much of each. Shoot from above, whole plate in.")),
                    .init(label: String(localized: "help.point.howWeUseIt", defaultValue: "How we use it"), text: String(localized: "help.food.p2.text", defaultValue: "Each food becomes calories, protein, carbs and fat · your day’s totals update on their own.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.food.p3.text", defaultValue: "Your meals and your check-ins side by side is how the meals that don’t agree with you show themselves.")),
                ],
                footnote: String(localized: "help.food.footnote", defaultValue: "Rough is fine. An approximate meal logged beats a perfect one skipped."),
                opens: .food
            ),
            HelpEntry(
                key: "library", group: .around,
                title: String(localized: "help.library.title", defaultValue: "Library"),
                lede: String(localized: "help.library.lede", defaultValue: "your reports and your reading"),
                body: String(localized: "help.library.body", defaultValue: "Two things live here: the reports the app writes from what you have logged, and material to read. The reading is chosen for your situation rather than for everyone."),
                points: [
                    .init(label: String(localized: "help.point.whatToDo", defaultValue: "What to do"), text: String(localized: "help.library.p1.text", defaultValue: "Open the card at the top for your reports; browse the rest when you’re curious.")),
                    .init(label: String(localized: "help.point.whatYouSee", defaultValue: "What you’re seeing"), text: String(localized: "help.library.p2.text", defaultValue: "Write-ups built from what you logged, and reading your practitioner picked for your situation · not for everyone.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.library.p3.text", defaultValue: "Catch up on a week you weren’t paying attention to, in two minutes.")),
                ],
                opens: .library
            ),
            HelpEntry(
                key: "checkin-hub", group: .checkins,
                title: String(localized: "help.checkins.title", defaultValue: "Your check-ins"),
                lede: String(localized: "help.checkins.lede", defaultValue: "two short sets of questions, once a day"),
                body: String(localized: "help.checkins.body", defaultValue: "This screen holds both daily check-ins and shows how they have been going. Each card is a summary and a door at the same time · tap one to do that check-in."),
                points: [
                    .init(label: String(localized: "help.point.whatToDo", defaultValue: "What to do"), text: String(localized: "help.checkins.p1.text", defaultValue: "Slide each one to roughly where you are, tap what fits. One minute, no right answer.")),
                    .init(label: String(localized: "help.point.whatWeLookAt", defaultValue: "What we look at"), text: String(localized: "help.checkins.p2.text", defaultValue: "How you actually felt · energy, sleep, mood, digestion. The one thing no device can report for you.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.checkins.p3.text", defaultValue: "These carry more weight in your scores than any device. They are how the app learns what normal feels like for you.")),
                ],
                footnote: String(localized: "help.checkins.footnote", defaultValue: "You can come back and edit today’s answers · saving again just updates them."),
                opens: .home
            ),
            HelpEntry(
                key: "confirm", group: .food,
                title: String(localized: "help.confirm.title", defaultValue: "Check the meal"),
                lede: String(localized: "help.confirm.lede", defaultValue: "the app’s best guess · your call"),
                body: String(localized: "help.confirm.body", defaultValue: "Here is what the app thinks you ate. It has already been saved to your day, so nothing is lost if you close this. Look it over and fix anything that is off."),
                points: [
                    .init(label: String(localized: "help.point.whatToDo", defaultValue: "What to do"), text: String(localized: "help.confirm.p1.text", defaultValue: "Look it over, fix anything that’s off. It’s already saved · nothing is lost if you close.")),
                    .init(label: String(localized: "help.confirm.p2.label", defaultValue: "The little symbols"), text: String(localized: "help.confirm.p2.text", defaultValue: "A quick read on each food · fibre, added sugar and friends. Tap one to see what it means.")),
                    .init(label: String(localized: "help.point.howItHelps", defaultValue: "How it helps you"), text: String(localized: "help.confirm.p3.text", defaultValue: "Every correction teaches the app your foods · next time it gets them right on its own.")),
                ],
                footnote: String(localized: "help.confirm.footnote", defaultValue: "This is an estimate, not a lab measurement. Close enough is close enough.")
            ),
        ]
    }
}

/// Help & FAQ (the Expo `profile-help.tsx` catalogue).
struct FAQCategory: Sendable, Equatable, Identifiable {
    struct Item: Sendable, Equatable, Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }
    let id: String
    let symbol: String
    let title: String
    let items: [Item]

    static var all: [FAQCategory] {
        [
            FAQCategory(id: "app", symbol: "iphone", title: String(localized: "faq.app.title", defaultValue: "Using the app"), items: [
                .init(question: String(localized: "faq.app.q1", defaultValue: "How do I log a meal?"), answer: String(localized: "faq.app.a1", defaultValue: "Tap the Food tab at the bottom of the screen. You can take a photo of your meal to have it analysed automatically, or describe it by voice or in writing.")),
                .init(question: String(localized: "faq.app.q2", defaultValue: "How does the daily check-in work?"), answer: String(localized: "faq.app.a2", defaultValue: "Each morning you will see a check-in prompt on the Home tab. It takes about 30 seconds and tracks your energy, digestion, mood, and sleep quality. This data feeds directly into your progress graphs and helps your nutritionist adjust your plan.")),
                .init(question: String(localized: "faq.app.q3", defaultValue: "Can I use the app offline?"), answer: String(localized: "faq.app.a3", defaultValue: "You can browse most screens offline. Meal photo analysis and syncing require an internet connection.")),
            ]),
            FAQCategory(id: "nutrition", symbol: "fork.knife", title: String(localized: "faq.nutrition.title", defaultValue: "Nutrition & tracking"), items: [
                .init(question: String(localized: "faq.nutrition.q1", defaultValue: "How are my macro targets calculated?"), answer: String(localized: "faq.nutrition.a1", defaultValue: "Your targets are based on your weight, height, age, activity level, and health goals · adjusted for your goal (maintain, lose, gain, performance). Your nutritionist can override these at any time.")),
                .init(question: String(localized: "faq.nutrition.q2", defaultValue: "Why does the AI analysis sometimes look wrong?"), answer: String(localized: "faq.nutrition.a2", defaultValue: "AI meal analysis is an estimate, not a lab measurement. For packaged foods, try photographing the nutrition label directly for higher accuracy.")),
                .init(question: String(localized: "faq.nutrition.q3", defaultValue: "What does the nutrition score mean?"), answer: String(localized: "faq.nutrition.a3", defaultValue: "The score (0-100) reflects how well your meal supports your specific health goals · it considers inflammation markers, energy quality, gut health, and digestibility. It is not a simple calorie or \"healthiness\" score.")),
                .init(question: String(localized: "faq.nutrition.q4", defaultValue: "How far back can I see my food history?"), answer: String(localized: "faq.nutrition.a4", defaultValue: "You can scroll back through your log indefinitely. The progress charts show rolling 7-day and 30-day averages.")),
            ]),
            FAQCategory(id: "account", symbol: "person.crop.circle", title: String(localized: "faq.account.title", defaultValue: "Account & data"), items: [
                .init(question: String(localized: "faq.account.q1", defaultValue: "How do I update my personal information?"), answer: String(localized: "faq.account.a1", defaultValue: "Contact your FunctionAlps practitioner or email contact@functionalps.ch. Your baseline (age, height, weight, activity) can be updated from your profile in the app.")),
                .init(question: String(localized: "faq.account.q2", defaultValue: "Can I export my data?"), answer: String(localized: "faq.account.a2", defaultValue: "Yes. Go to Profile > Settings > Privacy & data > Export my data. You get a complete copy as JSON.")),
                .init(question: String(localized: "faq.account.q3", defaultValue: "How do I delete my account?"), answer: String(localized: "faq.account.a3", defaultValue: "Go to Profile > Settings > Privacy & data > Delete my account. This permanently erases all your data within 30 days. This action cannot be undone. Your practitioner will be notified.")),
                .init(question: String(localized: "faq.account.q4", defaultValue: "Is my data stored in Switzerland?"), answer: String(localized: "faq.account.a4", defaultValue: "Yes. FunctionAlps is registered in Switzerland and your data is stored on EU-compliant servers. We comply with the Swiss Federal Act on Data Protection (nFADP) and GDPR.")),
            ]),
        ]
    }
}
