import SwiftUI

// The episode page's glass cards. Each renders only when the API sent its document. Text is the backend's;
// labels are the members web's `show.*` strings.

/// The small grey uppercase label at the top of every card ("NOTES", "RESEARCH" …).
private struct ShowCardLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.3)
                .foregroundStyle(FAColor.stone)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
        }
    }
}

private struct ShowBullets: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(FALibraryColor.gold).frame(width: 5, height: 5).padding(.top, 7)
                    Text(item).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x3B3A33))
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ShowMarkdown: View {
    let md: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(LibraryMarkdown.parse(md).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

struct ShowNotesCard: View {
    let notes: ShowNotes

    var body: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 8) {
                ShowCardLabel(text: String(localized: "show.notesEyebrow", defaultValue: "Notes"))
                if !notes.summary.showIsBlank { ShowMarkdown(md: notes.summary) }
                if !notes.keyActions.isEmpty { ShowBullets(items: notes.keyActions) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

struct ShowResearchCard: View {
    let research: ShowResearch
    @State private var selected = 0

    private struct Column: Identifiable {
        let id: Int
        let label: String
        let items: [String]
        let tint: Color
    }

    private var columns: [Column] {
        [
            Column(id: 0, label: String(localized: "show.know", defaultValue: "What we know"), items: research.synthesis.know, tint: Color(hex: 0xEDF4EF, opacity: 0.9)),
            Column(id: 1, label: String(localized: "show.likelyShort", defaultValue: "Likely"), items: research.synthesis.likely, tint: Color(hex: 0xF0E6D0, opacity: 0.9)),
            Column(id: 2, label: String(localized: "show.uncertainShort", defaultValue: "Uncertain"), items: research.synthesis.uncertain, tint: Color(hex: 0xF2EEE6, opacity: 0.9)),
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        let cols = columns
        let current = cols.first { $0.id == selected } ?? cols.first
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 10) {
                ShowCardLabel(text: String(localized: "show.researchEyebrow", defaultValue: "Research"),
                          trailing: research.references.isEmpty ? nil : sourcesLabel)
                if !cols.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(cols) { col in
                            let on = col.id == current?.id
                            Button { selected = col.id } label: {
                                Text(col.label)
                                    .font(FATypography.sans(11, on ? .bold : .semibold, relativeTo: .caption))
                                    .foregroundStyle(FAColor.charcoal)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(col.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(on ? FAColor.forest.opacity(0.55) : Color.clear, lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if let current { ShowBullets(items: current.items) }
                }
                if !research.references.isEmpty {
                    Divider().overlay(Color(hex: 0x1A1A16, opacity: 0.06))
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(research.references.enumerated()), id: \.offset) { _, ref in reference(ref) }
                    }
                    Text(String(localized: "show.sourcesNote", defaultValue: "Every source is checked on PubMed before it is published."))
                        .font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private var sourcesLabel: String {
        let n = research.references.count
        return n == 1 ? String(localized: "show.oneSource", defaultValue: "1 source") : String(localized: "show.sourcesCount", defaultValue: "\(n) sources")
    }

    private func reference(_ ref: ShowReference) -> some View {
        let meta = [ref.authors, ref.journal, ref.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(ref.title.isEmpty ? "PMID \(ref.pmid)" : ref.title)
                .font(FATypography.sans(12, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            if !meta.isEmpty {
                Text(meta).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
            if let url = ShowLogic.pubmedURL(ref.pmid) {
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Text("PMID \(ref.pmid)")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(FATypography.sans(10.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                }
            }
            if !ref.note.isEmpty {
                Text(ref.note).font(FATypography.sans(10.5, relativeTo: .caption)).italic().foregroundStyle(FAColor.stone)
            }
        }
    }
}

/// "The week · experiment": done days folded into one line, today's step with "Mark today done", the days ahead,
/// and the daily reminder. Days go in order, one per Zurich calendar day — the same rule as the members web.
struct ShowExperimentCard: View {
    @Bindable var model: ShowEpisodeViewModel
    let guide: ShowGuide

    var body: some View {
        let days = guide.experiment.days
        let state = model.state
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                ShowCardLabel(text: "\(String(localized: "show.weekEyebrow", defaultValue: "The week")) · \(String(localized: "show.piece.experiment", defaultValue: "Experiment"))",
                          trailing: progressLabel(state, total: days.count))
                    .padding(.bottom, 6)
                if !guide.experiment.title.showIsBlank || !guide.experiment.goal.showIsBlank {
                    (Text(guide.experiment.title.showIsBlank ? "" : guide.experiment.title + ". ").font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundColor(FAColor.charcoal)
                     + Text(guide.experiment.goal).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundColor(FAColor.stone))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }
                if let state {
                    tracked(days, state)
                } else {
                    ForEach(days) { d in dayRow(d, emphasis: false) }
                }
                if let state, state.nextDay == nil {
                    Text(String(localized: "show.expComplete", defaultValue: "Week complete. What did you notice?"))
                        .font(FATypography.sans(12.5, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forest)
                        .padding(.top, 8)
                    if !guide.reflection.isEmpty { ShowBullets(items: guide.reflection).padding(.top, 6) }
                }
                if let state, state.nextDay != nil {
                    reminderRow
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private func progressLabel(_ state: ShowLogic.ExperimentState?, total: Int) -> String? {
        guard let state, !state.done.isEmpty else { return nil }
        let current = min(state.nextDay ?? total, total)
        return String(localized: "show.dayOfTotal", defaultValue: "Day \(current) of \(total)")
    }

    @ViewBuilder
    private func tracked(_ days: [ShowGuide.Day], _ state: ShowLogic.ExperimentState) -> some View {
        let done = days.filter { state.done.contains($0.day) }
        if !done.isEmpty {
            row(first: true) {
                HStack(spacing: -6) {
                    ForEach(done.prefix(3)) { _ in
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(FAColor.forest, in: Circle())
                            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                    }
                }
                .accessibilityHidden(true)
                Text(doneLabel(done.map(\.day))).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
            }
        }
        if let next = days.first(where: { $0.day == state.nextDay }) {
            row(first: done.isEmpty) {
                Circle().strokeBorder(FAColor.forestSoft, lineWidth: 2).frame(width: 22, height: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if state.doneToday {
                        Text("\(String(localized: "show.dayN", defaultValue: "Day \(next.day)")) · \(next.action)")
                            .font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
                        Text(String(localized: "show.doneToday", defaultValue: "Done for today. Day \(next.day) tomorrow."))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                    } else {
                        Text("\(String(localized: "show.today", defaultValue: "Today")) · \(next.action)")
                            .font(FATypography.sans(12.5, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
                        Button { Task { await model.markToday() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                Text(model.marking ? String(localized: "show.saving", defaultValue: "Saving...") : String(localized: "show.markToday", defaultValue: "Mark today done"))
                                    .font(FATypography.sans(11.5, .bold, relativeTo: .caption))
                            }
                            .foregroundStyle(FAColor.cream)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(FAColor.forest, in: Capsule())
                            .opacity(model.marking ? 0.7 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.marking)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(days.filter { $0.day > next.day && !state.done.contains($0.day) }) { d in dayRow(d, emphasis: false) }
        }
    }

    private func doneLabel(_ done: [Int]) -> String {
        guard let first = done.first, let last = done.last else { return "" }
        if done.count == 1 { return String(localized: "show.dayDone", defaultValue: "Day \(first) · done") }
        return String(localized: "show.daysDone", defaultValue: "Days \(first)–\(last) · done")
    }

    private func dayRow(_ d: ShowGuide.Day, emphasis: Bool) -> some View {
        row(first: false) {
            Text("\(d.day)").font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                .frame(width: 22, height: 22).background(Color.white.opacity(0.7), in: Circle())
                .overlay { Circle().strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
                .accessibilityHidden(true)
            Text("\(String(localized: "show.dayN", defaultValue: "Day \(d.day)")) · \(d.action)")
                .font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.stone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<Content: View>(first: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .overlay(alignment: .top) { if !first { Rectangle().fill(Color(hex: 0x1A1A16, opacity: 0.07)).frame(height: 1) } }
    }

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { model.reminderOn }, set: { on in Task { await model.setReminder(on) } })) {
                Text(String(localized: "show.remindDaily", defaultValue: "Remind me every day"))
                    .font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.charcoal)
            }
            .tint(FAColor.forestSoft)
            if model.reminderDenied {
                Text(String(localized: "notif.denied.title", defaultValue: "Notifications are off for FunctionAlps"))
                    .font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x1A1A16, opacity: 0.07)).frame(height: 1) }
    }
}

struct ShowArticleCard: View {
    let article: ShowArticle
    @State private var open = false

    var body: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 8) {
                ShowCardLabel(text: String(localized: "show.articleEyebrow", defaultValue: "Article"))
                Text(article.title.showIsBlank ? String(localized: "show.articleEyebrow", defaultValue: "Article") : article.title)
                    .font(FATypography.display(18, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(.easeInOut(duration: 0.25)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text(String(localized: "show.readArticle", defaultValue: "Read the article"))
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(FATypography.sans(12, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forest)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay { Capsule().strokeBorder(FAColor.forest.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                if open {
                    VStack(alignment: .leading, spacing: 0) {
                        if !article.intro.showIsBlank { ShowMarkdown(md: article.intro) }
                        ForEach(Array(article.sections.enumerated()), id: \.offset) { _, section in
                            if !section.heading.isEmpty {
                                Text(section.heading).font(FATypography.display(16, relativeTo: .headline)).foregroundStyle(FAColor.charcoal)
                                    .padding(.top, 8).padding(.bottom, 6)
                            }
                            ShowMarkdown(md: section.body)
                        }
                        if !article.takeaways.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "show.takeaways", defaultValue: "Takeaways"))
                                    .font(FATypography.sans(12, .semibold, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x9A7228))
                                ShowBullets(items: article.takeaways)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FALibraryColor.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if !article.references.isEmpty { references }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "show.references", defaultValue: "References"))
                .font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            ForEach(Array(article.references.enumerated()), id: \.offset) { _, ref in
                if let url = ShowLogic.pubmedURL(ref) {
                    Link("PMID \(ref)", destination: url)
                        .font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                } else {
                    Text(ref).font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                }
            }
        }
        .padding(.top, 10)
    }
}

struct ShowFaqCard: View {
    let faq: ShowFaq
    @State private var open: Set<Int> = [0]

    var body: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                ShowCardLabel(text: String(localized: "show.faqEyebrow", defaultValue: "FAQ"))
                Text(String(localized: "show.faqTitle", defaultValue: "Your questions"))
                    .font(FATypography.display(18, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    .padding(.top, 6).padding(.bottom, 4)
                ForEach(Array(faq.items.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if open.contains(i) { open.remove(i) } else { open.insert(i) }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.question).font(FATypography.sans(13, .semibold, relativeTo: .body)).foregroundStyle(FAColor.charcoal)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(FALibraryColor.gold)
                                    .rotationEffect(.degrees(open.contains(i) ? 45 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(open.contains(i) ? .isSelected : [])
                        if open.contains(i), !item.answer.showIsBlank {
                            ShowMarkdown(md: item.answer)
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color(hex: 0x1A1A16, opacity: 0.06)).frame(height: 1) } }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}
