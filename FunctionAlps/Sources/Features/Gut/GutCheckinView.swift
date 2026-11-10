import SwiftUI
import Observation

/// "How's your gut today?" — the Expo `gut-intelligence-checkin.tsx`: three dimension cards, an optional
/// note, one save. Re-opening the same day edits the saved answers.
struct GutCheckinView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: GutCheckinViewModel?

    var body: some View {
        ZStack {
            if let model { GutCheckinScreen(model: model) { dismiss() } }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = GutCheckinViewModel(gut: dependencies.gut, members: dependencies.members, auth: dependencies.auth)
                model = m
                await m.prefill()
            }
        }
    }
}

@MainActor
@Observable
final class GutCheckinViewModel {
    var answers: GutAnswerSet = .blank
    var notes = ""
    var notesOpen = false
    var redFlags: RedFlags = .none
    var isSaving = false
    var saveError: String?
    private(set) var editing = false
    private(set) var todayMeals: [MealLog] = []
    private(set) var reactions: [String: MealReaction] = [:]
    private(set) var loaded = false

    private let gut: GutService
    private let members: MemberService
    private let auth: AuthService

    init(gut: GutService, members: MemberService, auth: AuthService) {
        self.gut = gut; self.members = members; self.auth = auth
    }

    func prefill() async {
        defer { loaded = true }
        do {
            let member = try await members.currentMember()
            let state = try await gut.load(patientId: member.patientId)
            todayMeals = state.meals.filter { ISO8601.dayString($0.loggedAt) == state.day }
            reactions = state.reactions
            if let today = state.today {
                answers = today.answers
                notes = today.notes ?? ""
                notesOpen = !notes.isEmpty
                redFlags = today.redFlags
                editing = true
            }
            // Today's rated meals feed the reactions read (the saved score wins when editing — Expo behaviour).
            if answers[.reactions]?.specials.reactionsScore == nil {
                answers[.reactions, default: .empty].specials.reactionsScore = GutEngine.mealReactionsScore(todayMeals.compactMap { reactions[$0.id] })
            }
            #if DEBUG
            if Showcase.isDigestionShot {
                answers[.comfort] = GutAnswers(sliders: ["comfort": 66])
                answers[.stool] = GutAnswers(sliders: ["ease": 72], specials: GutSpecials(bristol: 4, frequency: 2))
                if Showcase.screen == .checkinNote {
                    notes = "Felt bloated after lunch, better after the walk."
                    notesOpen = true
                }
            }
            #endif
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "gut.prefill")
            if case .unauthorized = error { await auth.handleUnauthorized() }
        } catch {
            Log.data.error("gut.prefill: \(String(describing: error), privacy: .public)")
        }
    }

    var ratedMeals: [RatedMeal] {
        var out: [RatedMeal] = []
        for m in todayMeals {
            if let r = reactions[m.id], r.overall != nil { out.append(RatedMeal(meal: m, reaction: r)) }
        }
        return out
    }

    func save() async -> Bool {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let member = try await members.currentMember()
            _ = try await gut.save(patientId: member.patientId, answers: answers, notes: notes, redFlags: redFlags)
            return true
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "gut.save")
            if case .unauthorized = error { await auth.handleUnauthorized(); return false }
            saveError = error.userMessage
        } catch {
            saveError = String(describing: error)
        }
        return false
    }
}

/// "Anything serious to flag?" — the six red-flag symptoms (Expo `red-flags.ts`, the `red_flag_*` columns).
/// Stored as booleans, never scored, never linked to a food. Ticking one shows the doctor signpost right here
/// and on Home, and reaches the practitioner as one `red_flag` event.
/// Owner, 2026-11-10: a SMALL card with a "be aware" sign, closed until opened — and open by itself whenever a
/// flag is already ticked, so nothing serious hides behind a fold.
struct GutRedFlagsCard: View {
    @Binding var flags: RedFlags
    @State private var open = false

    private var expanded: Bool { open || flags.any }

    var body: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ProfilePalette.red)
                            .frame(width: 28, height: 28)
                            .background(ProfilePalette.red.opacity(0.10), in: Circle())
                            .accessibilityHidden(true)
                        Text(String(localized: "gut.redflags.title", defaultValue: "Anything serious to flag?"))
                            .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Spacer(minLength: 4)
                        if !flags.any {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(flags.any)
                .accessibilityHint(expanded ? "" : String(localized: "gut.redflags.openHint", defaultValue: "Shows the symptoms to flag"))

                if expanded {
                    Text(String(localized: "gut.redflags.intro", defaultValue: "Optional · these are for a doctor's eye, not a nutrition read. Tick anything that applies today."))
                        .font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    PillGroupView(
                        title: nil,
                        options: RedFlag.allCases.map { PillOption(key: $0.rawValue, label: $0.label) },
                        isOn: { key in RedFlag(rawValue: key).map(flags.contains) ?? false },
                        onToggle: { key in if let flag = RedFlag(rawValue: key) { flags.toggle(flag) } },
                        accent: ProfilePalette.red
                    )
                    .padding(.top, -12)
                    if flags.any {
                        Text(RedFlags.signpost)
                            .font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .animation(.easeInOut(duration: 0.2), value: flags.any)
    }
}

/// A meal rated today, for the reactions card.
struct RatedMeal: Identifiable, Sendable, Equatable {
    let meal: MealLog
    let reaction: MealReaction
    var id: String { meal.id }
}

struct GutCheckinScreen: View {
    @Bindable var model: GutCheckinViewModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.inkSecondary).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "gut.checkin.title", defaultValue: "How's your\ngut today?"))
                        .font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink).lineSpacing(3)
                    Text(model.editing
                         ? String(localized: "gut.checkin.editing", defaultValue: "Editing today's gut check-in · tweak anything and save.")
                         : String(localized: "gut.checkin.intro", defaultValue: "Three quick reads · comfort, stool, and food reactions."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, 6)
                .padding(.bottom, 4)

                ForEach(GutSchema.dimensions) { spec in
                    GutDimensionCard(spec: spec, answers: binding(spec.key), ratedMeals: spec.key == .reactions ? model.ratedMeals : [])
                }

                GutRedFlagsCard(flags: $model.redFlags)

                notesBlock

                if let error = model.saveError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "gut.save.errorTitle", defaultValue: "Couldn't save your check-in")).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.red)
                        Text(String(localized: "gut.save.errorBody", defaultValue: "Your answers are still here · tap Save to try again. If it keeps failing, let us know and we'll look into it."))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(3)
                        if BuildInfo.showsTechnicalDetails { Text(error).font(FATypography.caption).foregroundStyle(FAColor.inkMuted) }
                    }
                    .padding(14)
                    .background(ProfilePalette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ProfilePalette.red.opacity(0.3), lineWidth: 1))
                }

                FAButton(title: model.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "gut.save", defaultValue: "Save gut check-in"), isLoading: model.isSaving, isEnabled: model.loaded) {
                    Task { if await model.save() { onSaved() } }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func binding(_ key: GutDimKey) -> Binding<GutAnswers> {
        Binding(get: { model.answers[key] ?? .empty }, set: { model.answers[key] = $0 })
    }

    private var notesBlock: some View {
        VoiceNoteBlock(
            addTitle: String(localized: "gut.notes.add", defaultValue: "Add a note (optional)"),
            placeholder: String(localized: "gut.notes.placeholder", defaultValue: "Add meal context, symptom timing, stool changes, or anything relevant."),
            text: $model.notes, open: $model.notesOpen
        )
    }
}

/// One gut dimension: header + score, the stool inputs (Bristol + frequency) or today's rated meals, the
/// slider, then the pill modules the read triggers (`DimensionCard.tsx` for the gut schema).
struct GutDimensionCard: View {
    let spec: GutDimensionSpec
    @Binding var answers: GutAnswers
    var ratedMeals: [RatedMeal] = []

    private var accent: Color { Color(hex: spec.accentHex) }
    private var score: Int? { GutEngine.dimensionOverall(spec.key, answers) }
    private var visible: [GutPillModule] { GutSchema.visiblePills(spec, answers) }
    private func after(_ anchor: String) -> [GutPillModule] { visible.filter { $0.after == anchor } }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(spec.title).font(FATypography.title).foregroundStyle(FAColor.ink)
                    Spacer()
                    Text(score.map(String.init) ?? "·")
                        .font(FATypography.headline)
                        .foregroundStyle(score.map { FunctionalSliderView.ramp[CheckinEngine.stateRampIndex(Double($0))] } ?? FAColor.inkMuted)
                        .monospacedDigit()
                }
                .padding(.bottom, 14)
                .accessibilityElement(children: .combine)

                // Stool, in the owner's order (2026-11-10): how often, how easy, THEN the type — Bristol last.
                if spec.key == .stool { frequencyInput.padding(.bottom, 12) }
                if spec.key == .reactions, !ratedMeals.isEmpty { mealsBlock.padding(.bottom, 10) }

                FunctionalSliderView(spec: spec.slider, value: Binding(get: { answers.sliders[spec.slider.key] }, set: { answers.sliders[spec.slider.key] = $0 }))
                pillBlock(after(spec.slider.key))

                if spec.key == .stool { bristolInput.padding(.top, 8) }
            }
        }
        #if DEBUG
        .task {
            guard spec.key == .stool, Showcase.screen == .bristolChart else { return }
            try? await Task.sleep(for: .seconds(3))
            chartOpen = true
        }
        #endif
        .sheet(isPresented: $chartOpen) {
            BristolChartSheet(selected: answers.specials.bristol, accent: accent) { answers.specials.bristol = $0 }
                .presentationDetents([.large])
        }
    }

    @State private var chartOpen = false

    /// The type, 1–7, with the chart one tap away: a small card showing the drawings, which opens the full
    /// chart over the check-in — tap a row there and it answers.
    private var bristolInput: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(FAColor.separator).padding(.bottom, 10)
            Button { chartOpen = true } label: {
                HStack(spacing: 12) {
                    if let thumb = FAMedia.image(BristolChart.imageName, ext: BristolChart.imageExt) {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(BristolChart.aspectRatio, contentMode: .fit)
                            .frame(height: 64)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "gut.bristol.title", defaultValue: "Stool type (Bristol scale)"))
                            .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Text(answers.specials.bristol.map { String(localized: "gut.bristol.chart.yours", defaultValue: "Yours · \(GutSchema.bristolLabel($0)) · tap to see the chart") }
                             ?? String(localized: "gut.bristol.chart.open", defaultValue: "See what each type looks like · tap the one that's yours"))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted).accessibilityHidden(true)
                }
                .padding(10)
                .contentShape(Rectangle())
                .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
            }
            .buttonStyle(.plain)
            PillSelectView(title: nil, options: GutSchema.bristolOptions,
                           value: Binding(get: { answers.specials.bristol.map(String.init) }, set: { answers.specials.bristol = $0.flatMap(Int.init) }), accent: accent)
        }
    }

    private var frequencyInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "gut.frequency.title", defaultValue: "Frequency (stools / 24h)")).font(FATypography.sans(11, .medium, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                HStack(spacing: 14) {
                    stepButton("−", tint: FAColor.inkSecondary, fill: Color.white.opacity(0.45)) { answers.specials.frequency = max(0, (answers.specials.frequency ?? 0) - 1) }
                    Text("\(answers.specials.frequency ?? 0)").font(FATypography.sans(26, .bold, relativeTo: .title)).foregroundStyle(FAColor.ink).frame(minWidth: 72).monospacedDigit()
                    stepButton("+", tint: accent, fill: accent.opacity(0.13)) { answers.specials.frequency = min(15, (answers.specials.frequency ?? 0) + 1) }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func stepButton(_ glyph: String, tint: Color, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: 20, weight: .medium)).foregroundStyle(tint).frame(width: 40, height: 40).background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(glyph == "+" ? String(localized: "action.increase", defaultValue: "Increase") : String(localized: "action.decrease", defaultValue: "Decrease"))
    }

    /// Today's rated meals, read-only, with the Expo `feltSummary` line.
    private var mealsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "gut.todayMeals", defaultValue: "Today's meals").uppercased()).font(FATypography.label).foregroundStyle(FAColor.inkSecondary).tracking(0.4)
            ForEach(ratedMeals) { pair in
                HStack {
                    Text(pair.meal.name ?? pair.meal.mealType?.rawValue.capitalized ?? String(localized: "gut.meal", defaultValue: "Meal")).font(FATypography.sans(13, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1)
                    Spacer()
                    Text(Self.feltSummary(pair.reaction)).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func feltSummary(_ r: MealReaction) -> String {
        let bl = r.bloating ?? 0, gas = r.gas ?? 0, full = r.fullness ?? 0, overall = r.overall ?? 0
        let worst = max(bl, gas, full)
        if worst <= 3 && overall >= 7 { return String(localized: "gut.felt.satWell", defaultValue: "sat well") }
        if bl >= 7 { return String(localized: "gut.felt.bloated", defaultValue: "felt bloated") }
        if gas >= 7 { return String(localized: "gut.felt.gassy", defaultValue: "felt gassy") }
        if full >= 7 { return String(localized: "gut.felt.heavy", defaultValue: "felt heavy") }
        if worst >= 5 {
            if bl == worst { return String(localized: "gut.felt.someBloating", defaultValue: "some bloating") }
            if gas == worst { return String(localized: "gut.felt.someGas", defaultValue: "some gas") }
            return String(localized: "gut.felt.full", defaultValue: "felt full")
        }
        if overall >= 6 { return String(localized: "gut.felt.okay", defaultValue: "felt okay") }
        return String(localized: "gut.felt.mixed", defaultValue: "mixed reaction")
    }

    private func pillBlock(_ modules: [GutPillModule], nested: Bool = false) -> AnyView {
        guard !modules.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if !nested { Divider().overlay(FAColor.separator).padding(.top, 6).padding(.bottom, 2) }
                ForEach(modules) { module in
                    PillGroupView(title: module.title, options: module.options, isOn: { (answers.pills[module.key] ?? []).contains($0) }, onToggle: { key in
                        let current = answers.pills[module.key] ?? []
                        answers.pills[module.key] = current.contains(key) ? current.filter { $0 != key } : current + [key]
                    }, accent: accent)
                    pillBlock(after(module.key), nested: true)
                }
            }
            .padding(.bottom, nested ? 0 : 8)
        )
    }
}
