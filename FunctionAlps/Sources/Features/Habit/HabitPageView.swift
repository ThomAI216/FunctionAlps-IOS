import SwiftUI

private let todayBlue = Color(hex: 0x2563EB)

/// A habit's page (Thomas, 2026-11-07, "stacked cards"): the streak first (once there is one), the video if it has one,
/// how to do it with its reads, the benefits to look for, what it tends to move. "Your own effects" is later: only
/// the neutral "after 10 days" line stands where it will be. Every habit word is the practice's (rule 6).
struct HabitPageView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let key: String
    @State private var model: HabitPageModel?
    @State private var softLock: LibrarySoftLock?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                backRow
                if let model { page(model) } else { FALoadingState().frame(minHeight: 240) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                model = HabitPageModel(key: key, track: dependencies.track, library: dependencies.library, members: dependencies.members)
            }
            await model?.load()
        }
        .sheet(item: $softLock) { lock in
            LibrarySoftLockSheet(lock: lock, today: model?.today, dayTitle: model?.dayTitle(lock.day))
        }
    }

    private var backRow: some View {
        HStack {
            Button { dismiss() } label: {
                Text("‹ " + String(localized: "plan.today.title", defaultValue: "Today's actions"))
                    .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                    .faFrost(cornerRadius: 14, horizontal: 12, vertical: 8)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if let moment = model?.content?.moment {
                Text(moment.label).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.cream)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(FAColor.forest, in: Capsule())
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func page(_ model: HabitPageModel) -> some View {
        switch model.phase {
        case .loading:
            FALoadingState().frame(minHeight: 240)
        case .failed(let message):
            FACard {
                FAErrorState(title: String(localized: "habit.page.error", defaultValue: "Couldn't load this habit"), message: message) {
                    Task { await model.load() }
                }
            }
        case .unauthorized:
            FACard {
                FAEmptyState(title: String(localized: "library.unauthorized.title", defaultValue: "Please sign in again"),
                             message: String(localized: "habit.unauthorized.message", defaultValue: "Your session ended. Sign in to see this habit."),
                             systemImage: "lock")
            }
        case .missing:
            FACard {
                FAEmptyState(title: String(localized: "habit.page.missing", defaultValue: "This habit is not in your actions"),
                             message: String(localized: "habit.page.missingMessage", defaultValue: "It may belong to another day."))
            }
        case .loaded:
            if let content = model.content { loaded(content, model) }
        }
    }

    @ViewBuilder
    private func loaded(_ c: HabitPageContent, _ model: HabitPageModel) -> some View {
        Text((String(localized: "habit.eyebrow", defaultValue: "Your habit") + " · " + c.whenText).uppercased())
            .font(FATypography.sans(10, .bold, relativeTo: .caption)).tracking(1.1).foregroundStyle(FAColor.forestSoft)
        Text(c.title).font(FATypography.display(28, relativeTo: .title)).foregroundStyle(FAColor.ink)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
        if let summary = c.summary {
            Text(summary).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let streak = c.streak { HabitStreakCard(streak: streak, today: c.today) }
        if let video = c.video {
            Button { router.push(.libraryVideo(video)) } label: { HabitVideoCard(video: video) }.buttonStyle(.plain)
        }
        if !c.steps.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(String(localized: "habit.how", defaultValue: "How to do it"))
                    ForEach(Array(c.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).").font(FATypography.callout).monospacedDigit().foregroundStyle(FAColor.inkSecondary)
                                .accessibilityHidden(true)
                            Text(step).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        // Its reads, titles only, two to a row, under the steps (a read of a day still to come is soft-locked).
        if !c.reads.isEmpty {
            LibraryReadGrid(items: c.reads) { read in
                LibraryReadCard(kicker: String(localized: "habit.read.kicker", defaultValue: "Article"), title: read.title, lockedDay: read.opensOn) {
                    open(read, model)
                }
            }
        }
        if !c.benefits.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(String(localized: "habit.benefits", defaultValue: "Benefits to look for"))
                    ForEach(c.benefits, id: \.self) { benefit in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(FAColor.forestSoft).accessibilityHidden(true)
                            Text(benefit).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        effects(c)
        doneButton(c, model)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(FATypography.headline).foregroundStyle(FAColor.ink).accessibilityAddTraits(.isHeader)
    }

    /// "How it affects you": what it tends to move (arrow AND words), and where the member's own effects will appear.
    @ViewBuilder
    private func effects(_ c: HabitPageContent) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(String(localized: "habit.effects", defaultValue: "How it affects you"))
                if !c.moves.isEmpty {
                    Text(String(localized: "habit.effects.tends", defaultValue: "It tends to")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    FlowLayout(spacing: 7) {
                        ForEach(c.moves) { move in
                            HStack(spacing: 4) {
                                Text(move.arrow).accessibilityHidden(true)
                                Text(move.label)
                            }
                            .font(FATypography.sans(13, .semibold, relativeTo: .callout))
                            .foregroundStyle(move.direction == .up ? FAColor.forestDark : Color(hex: 0x3730A3))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background((move.direction == .up ? FAColor.forestSoft : Color(hex: 0x6366F1)).opacity(0.16), in: Capsule())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(move.spoken)
                        }
                    }
                }
                Text(String(localized: "habit.effects.soon", defaultValue: "After 10 days with the habit, your check-ins will show how it moves your mood, energy, sleep and focus."))
                    .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func doneButton(_ c: HabitPageContent, _ model: HabitPageModel) -> some View {
        if c.canTick {
            Button { Task { await model.toggleToday() } } label: {
                HStack(spacing: 8) {
                    if c.doneToday { Image(systemName: "checkmark").accessibilityHidden(true) }
                    Text(c.doneToday
                         ? String(localized: "habit.done.undo", defaultValue: "Done today · tap to undo")
                         : String(localized: "habit.done", defaultValue: "Done today"))
                }
                .font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.cream)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(FAColor.forest.opacity(c.doneToday ? 0.7 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityAddTraits(c.doneToday ? .isSelected : [])
        }
    }

    private func open(_ read: HabitPageRead, _ model: HabitPageModel) {
        if let day = read.opensOn {
            softLock = LibrarySoftLock(day: day, titles: [read.title])
        } else {
            router.push(.read(read.slug))
        }
    }
}

// MARK: - The streak

/// The last 14 days as dots, how many in a row, and the blue dot of today ("You are here"). No ring.
private struct HabitStreakCard: View {
    let streak: HabitPageContent.Streak
    let today: Int

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(FAColor.streak).accessibilityHidden(true)
                    Text("\(streak.run)").font(FATypography.display(22, relativeTo: .title3)).foregroundStyle(FAColor.ink).monospacedDigit()
                    Text(String(localized: "habit.streak.inARow", defaultValue: "in a row")).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "habit.streak.a11y", defaultValue: "\(streak.run) days in a row"))
                // Seven to a row would break the story: 14 dots on one line, each a flexible column.
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(streak.dots.enumerated()), id: \.element.id) { index, dot in
                        DotColumn(dot: dot, shift: Self.shift(index: index, count: streak.dots.count), date: Self.date(of: dot, today: today))
                    }
                }
                .padding(.top, 22)
            }
        }
    }
}

private extension HabitStreakCard {
    /// The calendar day of a dot, from the phone's today ("3 November" for VoiceOver).
    static func date(of dot: HabitDot, today: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dot.day - today, to: Date()) ?? Date()
    }

    /// Keeps the "You are here" label inside the card when today sits near either end (a column is about 20 points).
    static func shift(index: Int, count: Int) -> CGFloat {
        let half: CGFloat = 38, column: CGFloat = 20
        let left = max(0, half - (CGFloat(index) * column + column / 2))
        let right = max(0, half - (CGFloat(count - 1 - index) * column + column / 2))
        return left - right
    }
}

private struct DotColumn: View {
    let dot: HabitDot
    var shift: CGFloat = 0
    let date: Date

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                dotShape.frame(width: 18, height: 18)
                if dot.isToday {
                    Text(String(localized: "habit.streak.here", defaultValue: "You are here"))
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(todayBlue, in: Capsule())
                        .offset(x: shift, y: -22)
                        .accessibilityHidden(true)
                }
            }
            Text("\(dot.day)").font(FATypography.sans(9, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var dotShape: some View {
        switch dot.state {
        case .done:
            Circle().fill(dot.isToday ? todayBlue : FAColor.forestSoft)
                .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
        case .missed:
            Circle().fill(Color(hex: 0xE9C7D2)).overlay(Image(systemName: "minus").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x8A3A55)))
        case .notYet:
            Circle().strokeBorder(dot.isToday ? todayBlue : FAColor.inkMuted, lineWidth: dot.isToday ? 2.5 : 1.5)
        case .outside:
            Circle().fill(FAColor.inkMuted.opacity(0.18))
        }
    }

    /// Never colour alone: the state is said in words ("Done on 3 November"), and today is "Today".
    private var label: String {
        let day = date.formatted(.dateTime.day().month(.wide))
        let state: String = switch dot.state {
        case .done: String(localized: "habit.dot.done", defaultValue: "Done on \(day)")
        case .missed: String(localized: "habit.dot.missed", defaultValue: "Missed on \(day)")
        case .notYet: String(localized: "habit.dot.notYet", defaultValue: "\(day), not yet")
        case .outside: String(localized: "habit.dot.outside", defaultValue: "\(day), not part of this habit")
        }
        return dot.isToday ? String(localized: "habit.dot.today", defaultValue: "Today, \(state)") : state
    }
}

// MARK: - The video

private struct HabitVideoCard: View {
    let video: LibraryVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [FAColor.forest, FAColor.forestDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.95)).accessibilityHidden(true)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            Text(video.title).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .multilineTextAlignment(.leading)
            Text(String(localized: "habit.video.inApp", defaultValue: "Plays here, in the app") + " · " + LibraryVideoCopy.source(video))
                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(video.title). \(LibraryVideoCopy.source(video)). \(String(localized: "library.video.a11y", defaultValue: "Video"))")
        .accessibilityHint(String(localized: "library.video.hint", defaultValue: "Plays in the app"))
        .accessibilityAddTraits(.isButton)
    }
}
