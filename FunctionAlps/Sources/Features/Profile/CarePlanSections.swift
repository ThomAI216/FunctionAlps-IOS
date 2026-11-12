import SwiftUI

/// The cards of "My health plan" that show the clinician's own prose and lists (owner, 2026-11-10): the goals, the
/// supplements, the tests, the next review. Small views over plain values — `CarePlanView` decides what to show,
/// these only draw it. Every word is the clinician's (rule 6); the few labels are localised (rule 7).

/// The small uppercase heading every plan card starts with — the same as `CarePlanView.label`.
struct PlanCardLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
    }
}

/// Clinician prose (markdown-ish) split into paragraphs on blank lines.
enum PlanProse {
    static func paragraphs(_ text: String) -> [String] {
        var out: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { out.append(current.joined(separator: "\n")) }
            current = []
        }
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalised.components(separatedBy: "\n") {
            let line = clean(raw)
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { flush() } else if !line.isEmpty { current.append(line) }
        }
        flush()
        return out
    }

    /// Drops a leading heading mark ("## ") or bullet ("- ", "* ") — the app shows the words, not the markup.
    static func clean(_ line: String) -> String {
        var l = line.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("#") {
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.trimmingCharacters(in: .whitespaces)
        } else if l.hasPrefix("- ") || l.hasPrefix("* ") {
            l.removeFirst(2)
            l = l.trimmingCharacters(in: .whitespaces)
        }
        return l
    }

    /// Bold, italics and links from the clinician's markdown; the plain text when it does not parse.
    static func attributed(_ paragraph: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: paragraph, options: options)) ?? AttributedString(paragraph)
    }
}

/// The paragraphs of a clinician's text. `collapsible`: the first paragraph over four lines with "Read more".
struct PlanProseView: View {
    let text: String
    var collapsible = false
    @State private var expanded = false

    var body: some View {
        let paragraphs = PlanProse.paragraphs(text)
        let canCollapse = collapsible && (paragraphs.count > 1 || (paragraphs.first?.count ?? 0) > 220)
        VStack(alignment: .leading, spacing: 8) {
            if canCollapse && !expanded {
                if let first = paragraphs.first { paragraph(first).lineLimit(4) }
            } else {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in paragraph(p) }
            }
            if canCollapse {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? String(localized: "careplan.showLess", defaultValue: "Show less")
                                  : String(localized: "careplan.readMore", defaultValue: "Read more"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                        .frame(minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func paragraph(_ p: String) -> some View {
        Text(PlanProse.attributed(p))
            .font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One goal: what, and — where the clinician wrote them — "4 → 7 /10" and how often.
struct PlanGoalRow: View {
    let statement: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "target").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(statement).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    init(goal: CarePlan.Goal) {
        statement = goal.statement
        detail = [CarePlanLogic.goalRange(goal), goal.cadence].compactMap { $0 }.joined(separator: " · ")
    }

    init(text: String) {
        statement = text
        detail = nil
    }
}

/// "Your goals": the ones for the phase the member is in first, then the rest of the plan's.
struct PlanGoalsCard: View {
    let goals: [CarePlan.Goal]
    /// The string goals of the habit plan, used when the clinician has not written structured ones.
    let fallback: [String]
    let currentPhase: String?

    var body: some View {
        let now = CarePlanLogic.goalsNow(goals, currentPhase: currentPhase)
        let nowIds = Set(now.map(\.id))
        let later = goals.filter { !nowIds.contains($0.id) }
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                PlanCardLabel(String(localized: "careplan.yourGoals", defaultValue: "Your goals"))
                if goals.isEmpty {
                    ForEach(Array(fallback.enumerated()), id: \.offset) { _, text in PlanGoalRow(text: text) }
                } else {
                    if currentPhase != nil && !later.isEmpty { subheading(String(localized: "careplan.goals.now", defaultValue: "Now")) }
                    ForEach(now) { goal in PlanGoalRow(goal: goal) }
                    if !later.isEmpty {
                        if currentPhase != nil { subheading(String(localized: "careplan.goals.later", defaultValue: "Later in your plan")).padding(.top, 4) }
                        ForEach(later) { goal in PlanGoalRow(goal: goal).opacity(0.8) }
                    }
                }
            }
        }
    }

    private func subheading(_ text: String) -> some View {
        Text(text).font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
    }
}

/// "Supplements": what, how much, when — and why.
struct PlanSupplementsCard: View {
    let supplements: [CarePlan.Supplement]

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                PlanCardLabel(String(localized: "careplan.supplements", defaultValue: "Supplements"))
                ForEach(supplements) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "pills").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xA98FD0))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: 0xA98FD0, opacity: 0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(FATypography.sans(15, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            let how = [item.dosage, item.timing].compactMap { $0 }.joined(separator: " · ")
                            if !how.isEmpty {
                                Text(how).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                            if let why = item.why {
                                Text(why).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// "Tests": each with where it stands — a word and a shape, never only a colour.
struct PlanTestsCard: View {
    let tests: [CarePlan.Test]

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                PlanCardLabel(String(localized: "careplan.tests", defaultValue: "Tests"))
                ForEach(tests) { test in
                    HStack(alignment: .center, spacing: 10) {
                        Text(test.name).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        chip(test.state)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func chip(_ state: CarePlan.Test.State) -> some View {
        let (text, symbol): (String, String) = switch state {
        case .ordered: (String(localized: "careplan.test.ordered", defaultValue: "Ordered"), "clock")
        case .processing: (String(localized: "careplan.test.processing", defaultValue: "In the lab"), "hourglass")
        case .resulted: (String(localized: "careplan.test.resulted", defaultValue: "Results in"), "checkmark.circle")
        }
        return Label(text, systemImage: symbol)
            .font(FATypography.sans(12, .medium, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(FAColor.forestSoft.opacity(state == .resulted ? 0.22 : 0.12), in: Capsule())
    }
}

/// "Your next review": the date and what to expect until then.
struct PlanReviewCard: View {
    let date: String?
    let expectations: String?

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                PlanCardLabel(String(localized: "careplan.review", defaultValue: "Your next review"))
                if let date, !date.isEmpty {
                    Text(String(localized: "careplan.review.date", defaultValue: "Next review · \(date)"))
                        .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                }
                if let expectations, !expectations.isEmpty { PlanProseView(text: expectations) }
            }
        }
    }
}

/// A thin bar for how far into the plan the member is.
struct PlanProgressBar: View {
    let week: Int
    let total: Int

    var body: some View {
        let fraction = total > 0 ? min(1, max(0, Double(week) / Double(total))) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FAColor.forestSoft.opacity(0.16))
                Capsule().fill(FAColor.forestSoft).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
