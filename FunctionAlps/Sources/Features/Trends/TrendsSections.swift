import SwiftUI

// The Trends page's cards, top to bottom (owner-validated mockup v2, 2026-11-10).

// MARK: Your functional score

/// The ring of six equal segments, the score as the plain mean of the six signals, its curve and the six chips.
struct TrendsScoreCard: View {
    let page: TrendsEngine.Page
    /// "Learn about your functional score" — shown only when the practice's explanation of the score is loaded.
    var onLearn: (() -> Void)? = nil

    private func whole(_ v: Double?) -> String? { v.map { String(Int($0.rounded())) } }

    var body: some View {
        let score = page.score
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                TrendLabel(text: String(localized: "trends.score.title", defaultValue: "Your functional score"))
                    .padding(.bottom, 12)
                HStack(alignment: .center, spacing: 14) {
                    TrendScoreRing(chips: score.chips, value: score.value)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(score.value.map(String.init) ?? "·")
                                .font(FATypography.display(34, relativeTo: .largeTitle))
                                .foregroundStyle(score.value == nil ? FAColor.inkSecondary : FAColor.ink)
                            Text("/100").font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                        }
                        Text(TrendsFormat.averageLine(average: whole(score.average), previous: whole(score.previousAverage), days: page.window.days))
                            .font(FATypography.sans(12, relativeTo: .caption))
                            .foregroundStyle(FAColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if score.values.compactMap({ $0 }).count >= 2 {
                            TrendCurve(values: score.values, tint: FAColor.forest).frame(height: 36)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(score.chips) { chip in TrendChip(chip: chip) }
                }
                .padding(.top, 12)
                if let onLearn {
                    Button(action: onLearn) { SignalAboutLinkLabel(key: .score) }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                }
            }
        }
    }
}

private struct TrendChip: View {
    let chip: TrendsEngine.Chip

    var body: some View {
        let tint = Color(hex: chip.signal.tintHex)
        let value = chip.marker.map { String(Int(($0 / 10).rounded())) } ?? "–"
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(chip.signal.title)
                .font(FATypography.sans(11.5, relativeTo: .caption))
                .foregroundStyle(FAColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(value).font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 11)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, (chip.marker ?? 0) / 100))), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.signal.title): \(value)")
    }
}

// MARK: Your plan, day by day

/// Daily actions done against due, per day. Supplements: one row each with the days they were taken (the server's
/// observance strip). Until that strip is available the plan's own names are listed with the way to see them here.
struct TrendsPlanCard: View {
    let page: TrendsEngine.Page
    /// The supplements' day-by-day ticks (`TrendsEngine.supplementRows`); empty until they are read or when there are none.
    var supplementRows: [TrendsEngine.SupplementRow] = []

    private func barHeight(_ day: TrendsEngine.PlanDay, maxDue: Int) -> CGFloat {
        day.due == 0 ? 4 : max(10, CGFloat(day.due) / CGFloat(max(1, maxDue)) * 44)
    }

    var body: some View {
        let adherence = page.adherence
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                TrendLabel(text: String(localized: "trends.plan.title", defaultValue: "Your plan, day by day"))
                if adherence.due == 0 {
                    Text(String(localized: "trends.plan.empty", defaultValue: "No plan actions were due in this period."))
                        .font(FATypography.sans(13, relativeTo: .footnote))
                        .foregroundStyle(FAColor.inkSecondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "trends.plan.actions", defaultValue: "Daily actions"))
                            .font(FATypography.sans(14, .bold, relativeTo: .subheadline))
                            .foregroundStyle(FAColor.ink)
                        Spacer()
                        Text(String(localized: "trends.plan.done", defaultValue: "\(adherence.done) of \(adherence.due) done"))
                            .font(FATypography.sans(12.5, relativeTo: .caption))
                            .foregroundStyle(FAColor.inkSecondary)
                    }
                    strip(adherence)
                }
                if !supplementRows.isEmpty {
                    supplementStrips
                } else if !page.supplementNames.isEmpty {
                    supplements
                }
            }
        }
    }

    private func strip(_ adherence: TrendsEngine.Adherence) -> some View {
        let labelled = page.window.days <= 14
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(adherence.days) { day in
                let height = barHeight(day, maxDue: adherence.maxDue)
                let isToday = day.day == page.today
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(FAColor.forest.opacity(0.14))
                        if day.due > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(FAColor.forestSoft)
                                .frame(height: height * CGFloat(day.done) / CGFloat(day.due))
                        }
                    }
                    .frame(height: height)
                    .overlay {
                        if isToday { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(FAColor.forest, lineWidth: 1.5) }
                    }
                    if labelled {
                        Text(TrendsFormat.weekdayInitial(day.day))
                            .font(FATypography.sans(9, isToday ? .bold : .regular, relativeTo: .caption2))
                            .foregroundStyle(isToday ? FAColor.forest : FAColor.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 66, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "trends.plan.a11y", defaultValue: "Daily actions done: \(adherence.done) of \(adherence.due)"))
    }

    private var supplementStrips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "trends.plan.supplements", defaultValue: "Supplements"))
                    .font(FATypography.sans(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.ink)
                Spacer()
                Text(String(localized: "trends.supp.taken", defaultValue: "Taken per day"))
                    .font(FATypography.sans(12.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
            }
            ForEach(supplementRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name)
                            .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(FAColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if row.due > 0 {
                            Text(String(localized: "trends.supp.count", defaultValue: "\(row.taken) of \(row.due) days"))
                                .font(FATypography.sans(12, relativeTo: .caption))
                                .foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                    SupplementStrip(days: row.days)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
        .id("trends.supplements")
    }

    private var supplements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "trends.plan.supplements", defaultValue: "Supplements"))
                .font(FATypography.sans(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(FAColor.ink)
            TrendFlow(spacing: 6) {
                ForEach(Array(page.supplementNames.enumerated()), id: \.offset) { _, name in
                    TrendWordChip(text: name, isSupplement: true)
                }
            }
            Text(String(localized: "trends.plan.supplements.hint", defaultValue: "Tick them in your plan to see them here."))
                .font(FATypography.sans(12, relativeTo: .caption))
                .foregroundStyle(FAColor.inkSecondary)
        }
        .padding(.top, 4)
    }
}

// MARK: Your devices

struct TrendsDevicesCard: View {
    let devices: [TrendsEngine.Device]
    let onOpen: (TrendsEngine.Device) -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                TrendLabel(text: String(localized: "trends.devices.title", defaultValue: "Your devices"))
                    .padding(.bottom, 12)
                ForEach(Array(devices.enumerated()), id: \.element.id) { i, device in
                    if i > 0 { Divider().overlay(FAColor.separator).padding(.vertical, 10) }
                    Button { onOpen(device) } label: { row(device) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ device: TrendsEngine.Device) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.65))
                Image(systemName: WearableVendor.sourceSymbol(device.sourceId))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WearableVendor.sourceTint(device.sourceId))
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                HStack(spacing: 6) {
                    Circle().fill(FAColor.forestSoft).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(statusLine(device))
                        .font(FATypography.sans(12.5, relativeTo: .caption))
                        .foregroundStyle(FAColor.inkSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
        }
        .contentShape(Rectangle())
    }

    private func statusLine(_ device: TrendsEngine.Device) -> String {
        let sync = device.lastSync.map { HealthFormat.clock($0) }
        if device.isAppleHealth {
            guard let sync else { return String(localized: "trends.device.phone", defaultValue: "This iPhone") }
            return String(localized: "trends.device.phoneSync", defaultValue: "This iPhone · last sync \(sync)")
        }
        guard let sync else { return String(localized: "trends.device.connected", defaultValue: "Connected") }
        return String(localized: "trends.device.connectedSync", defaultValue: "Connected · last sync \(sync)")
    }
}

// MARK: Your signals

/// One signal: collapsed it is a glance; the first tap opens it in place, the second goes to its page.
struct TrendSignalRow: View {
    let page: TrendsEngine.Page
    let signal: TrendSignal
    let expanded: Bool
    /// The practice's short "What influences it" text for this signal (`signal_explanations.card_text`); nil hides the block.
    var cardText: String? = nil
    /// "Learn about <signal>" — pushes the signal's "About" page; nil hides the link.
    var onLearn: (() -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
        let facts = page.facts(signal)
        let tint = Color(hex: signal.tintHex)
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(tint).frame(width: 10, height: 10).accessibilityHidden(true)
                            Text(signal.title).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            if let badge = facts.badge {
                                Text(badge)
                                    .font(FATypography.sans(10.5, .medium, relativeTo: .caption2))
                                    .foregroundStyle(FAColor.inkSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.white.opacity(0.55), in: Capsule())
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: expanded ? "chevron.up" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FAColor.inkMuted)
                                .accessibilityHidden(true)
                        }
                        if expanded { expandedBody(facts, tint: tint) } else { collapsedBody(facts, tint: tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(expanded
                    ? String(localized: "trends.row.hint.open", defaultValue: "Opens the full details")
                    : String(localized: "trends.row.hint.expand", defaultValue: "Shows the last days"))
                if expanded, let cardText, !cardText.isEmpty { influencesBlock(cardText) }
            }
        }
        .animation(.easeOut(duration: 0.22), value: expanded)
    }

    /// "What influences it": the practice's own short text, and the way to its page.
    private func influencesBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.white.opacity(0.7))
            TrendLabel(text: String(localized: "signal.about.influences", defaultValue: "What influences it"))
                .padding(.top, 2)
            Text(text)
                .font(FATypography.sans(13, relativeTo: .footnote))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let onLearn, let key = SignalAboutKey(rawValue: signal.rawValue) {
                Button(action: onLearn) { SignalAboutLinkLabel(key: key) }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        }
    }

    private func headline(_ facts: TrendRowFacts) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(facts.big).font(FATypography.display(32, relativeTo: .title)).foregroundStyle(FAColor.ink)
                Text(facts.unit).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
            }
            if let sub = facts.sub {
                Text(sub).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
            }
        }
    }

    private func collapsedBody(_ facts: TrendRowFacts, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                headline(facts)
                Spacer(minLength: 8)
                TrendCurve(values: facts.plotted, tint: tint).frame(width: 120, height: 36)
            }
            Text(facts.averageLine).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
        }
    }

    private func expandedBody(_ facts: TrendRowFacts, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headline(facts)
            Text(facts.averageLine).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
            TrendCurve(values: facts.plotted, tint: tint, showAllDots: true, columns: true).frame(height: 80)
            TrendValueStrip(days: page.days, labels: facts.labels, tint: tint)
            TrendSentenceBox(text: page.sentence(signal))
            HStack(spacing: 6) {
                Spacer()
                Text(String(localized: "trends.row.more", defaultValue: "Tap again for full details"))
                    .font(FATypography.sans(11.5, .medium, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                Spacer()
            }
        }
    }
}

// MARK: What you ate, and how you felt

/// One meal line: its time, the photo when the app holds one, the dish, and the member's own reaction words —
/// never a score.
struct TrendMealRow: View {
    let meal: TrendsEngine.FoodMeal
    var showsPhoto = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(HealthFormat.clock(meal.time))
                .font(FATypography.sans(12, relativeTo: .caption))
                .foregroundStyle(FAColor.inkSecondary)
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)
                .padding(.top, 2)
            if showsPhoto { MealPhotoView(path: meal.photoPath, width: 46, height: 46, cornerRadius: 14) }
            VStack(alignment: .leading, spacing: 5) {
                Text(meal.name)
                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if meal.words.isEmpty {
                    Text(String(localized: "trends.meal.noReaction", defaultValue: "no reaction logged"))
                        .font(FATypography.sans(11.5, relativeTo: .caption))
                        .foregroundStyle(FAColor.inkMuted)
                } else {
                    TrendFlow(spacing: 5) {
                        ForEach(Array(meal.words.enumerated()), id: \.offset) { index, word in
                            TrendWordChip(text: word, tone: index < meal.tones.count ? meal.tones[index] : .neutral)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrendsFoodCard: View {
    let page: TrendsEngine.Page
    @State private var showAll = false

    private static let shownDays = 3

    var body: some View {
        let days = showAll ? page.food : Array(page.food.prefix(Self.shownDays))
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                TrendLabel(text: String(localized: "trends.food.title", defaultValue: "What you ate, and how you felt"))
                if page.food.isEmpty {
                    Text(String(localized: "trends.food.empty", defaultValue: "No meals logged in this period yet."))
                        .font(FATypography.sans(13, relativeTo: .footnote))
                        .foregroundStyle(FAColor.inkSecondary)
                } else {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(TrendsFormat.relativeDay(day.day, today: page.today))
                                .font(FATypography.sans(12, .bold, relativeTo: .caption))
                                .foregroundStyle(FAColor.inkSecondary)
                                .padding(.top, 4)
                            ForEach(day.meals) { meal in TrendMealRow(meal: meal) }
                        }
                    }
                    if page.food.count > Self.shownDays {
                        Button { showAll.toggle() } label: {
                            Text(showAll
                                 ? String(localized: "trends.food.fewer", defaultValue: "Show fewer days")
                                 : String(localized: "trends.food.all", defaultValue: "Show all \(page.food.count) days"))
                                .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(FAColor.forest)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

// MARK: Patterns shared by your practitioner

struct TrendsPatternsRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                FACard {
                    HStack(spacing: 6) {
                        Text(String(localized: "trends.patterns.row", defaultValue: "Patterns shared by your practitioner"))
                            .font(FATypography.sans(14.5, relativeTo: .subheadline))
                            .foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "· \(count)").font(FATypography.sans(14.5, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    }
                }
            }
            .buttonStyle(.plain)
            Text(String(localized: "trends.patterns.note", defaultValue: "Only what your practitioner has reviewed and shared appears here."))
                .font(FATypography.sans(11.5, relativeTo: .caption))
                .foregroundStyle(FAColor.inkMuted)
                .padding(.horizontal, 6)
        }
    }
}
