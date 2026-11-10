import SwiftUI

// The pieces of the Library home (Thomas, 2026-11-10): day cards, the reads tied to the habits, video tiles, the
// soft-lock sheet and the search results. Titles only, no striped covers; every card is the app's glass.

private let todayBlue = Color(hex: 0x2563EB)

// MARK: - Search field

struct LibrarySearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(FAColor.inkSecondary)
                .accessibilityHidden(true)
            TextField(String(localized: "library.search.placeholder", defaultValue: "Search"), text: $text)
                .font(FATypography.sans(14, relativeTo: .body))
                .foregroundStyle(FAColor.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
                .accessibilityLabel(String(localized: "library.search.label", defaultValue: "Search the library"))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(FAColor.inkMuted)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "library.search.clear", defaultValue: "Clear the search"))
            }
        }
        .faFrost(cornerRadius: 14, horizontal: 12, vertical: 8)
    }
}

// MARK: - Chips ("For you · Track · Watch")

struct LibraryChipRail: View {
    let active: LibraryViewModel.Anchor
    let showForYou: Bool
    let showWatch: Bool
    let onSelect: (LibraryViewModel.Anchor) -> Void

    var body: some View {
        HStack(spacing: 7) {
            if showForYou { chip(.forYou, String(localized: "library.chip.forYou", defaultValue: "For you")) }
            chip(.track, String(localized: "library.chip.track", defaultValue: "Track"))
            if showWatch { chip(.watch, String(localized: "library.chip.watch", defaultValue: "Watch")) }
        }
    }

    private func chip(_ anchor: LibraryViewModel.Anchor, _ title: String) -> some View {
        let on = active == anchor
        return Button { onSelect(anchor) } label: {
            Text(title).font(FATypography.sans(11.5, .bold, relativeTo: .caption)).foregroundStyle(on ? FAColor.cream : Color(hex: 0x4A4A42))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(on ? FAColor.forest : Color.white.opacity(0.66), in: Capsule())
                .overlay { Capsule().strokeBorder(on ? FAColor.forest : Color(hex: 0x1A1A16, opacity: 0.1), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - A day of the Foundation Track

struct LibraryDayCard: View {
    let group: LibraryDayGroup
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.0)
                    .foregroundStyle(group.phase == .today ? todayBlue : FALibraryColor.gold)
                ForEach(group.reads) { read in
                    Text(read.title)
                        .font(FATypography.display(13.5, relativeTo: .subheadline))
                        .foregroundStyle(group.isOpenable ? FAColor.charcoal : FAColor.stone)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                statusLine
            }
            .frame(width: 154, alignment: .leading)
            .frame(minHeight: 132, alignment: .topLeading)
            .padding(11)
            .background(Color.white.opacity(group.isOpenable ? 0.62 : 0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: group.phase == .today ? 2 : 1, dash: group.isOpenable ? [] : [4, 3]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(group.isOpenable
                           ? String(localized: "library.day.hint", defaultValue: "Opens this day's reads")
                           : String(localized: "library.day.hintLocked", defaultValue: "Shows when this day opens"))
    }

    private var eyebrow: String {
        let day = String(localized: "library.day.n", defaultValue: "Day \(group.day)")
        return group.phase == .today ? "\(day) · \(String(localized: "library.day.today", defaultValue: "today"))" : day
    }

    private var border: Color {
        switch group.phase {
        case .today: todayBlue
        case .future: Color(hex: 0x4A8A5C, opacity: 0.35)
        default: Color(hex: 0x4A8A5C, opacity: 0.22)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Image(systemName: statusSymbol).font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            Text(statusText).font(FATypography.sans(10, group.phase == .today ? .bold : .medium, relativeTo: .caption2))
        }
        .foregroundStyle(group.phase == .today && group.status != .read ? todayBlue : FAColor.stone)
    }

    private var statusSymbol: String {
        switch group.status {
        case .read: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .unread: "circle"
        case .new: "sparkle"
        case .locked: "lock.fill"
        }
    }

    private var statusText: String { LibraryDayCopy.status(group.status) }

    private var accessibilityLabel: String {
        let day = group.phase == .today
            ? String(localized: "library.day.a11yToday", defaultValue: "Day \(group.day), today")
            : String(localized: "library.day.n", defaultValue: "Day \(group.day)")
        return ([day] + group.reads.map(\.title) + [statusText]).joined(separator: ". ")
    }
}

enum LibraryDayCopy {
    static func status(_ status: LibraryDayGroup.Status) -> String {
        switch status {
        case .read: String(localized: "library.day.read", defaultValue: "Read")
        case .partial(let done, let total): String(localized: "library.day.partial", defaultValue: "\(done) of \(total) read")
        case .unread: String(localized: "library.day.unread", defaultValue: "Not read yet")
        case .new: String(localized: "library.day.new", defaultValue: "New")
        case .locked(let day): String(localized: "library.day.opensOn", defaultValue: "Opens on day \(day)")
        }
    }
}

// MARK: - A read as a card (titles only)

struct LibraryReadCard: View {
    let kicker: String?
    let title: String
    var lockedDay: Int? = nil
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if let kicker, !kicker.isEmpty {
                        Text(kicker.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.0)
                            .foregroundStyle(FALibraryColor.gold).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Text(title).font(FATypography.display(14, relativeTo: .subheadline))
                        .foregroundStyle(lockedDay == nil ? FAColor.charcoal : FAColor.stone)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let lockedDay {
                        Label(LibraryDayCopy.status(.locked(opensOnDay: lockedDay)), systemImage: "lock.fill")
                            .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone).padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel([kicker, title, lockedDay.map { LibraryDayCopy.status(.locked(opensOnDay: $0)) }].compactMap { $0 }.joined(separator: ". "))
    }
}

/// Two to a row; not a lazy grid so the cards of a row share one height.
struct LibraryReadGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { item in cell(item).frame(maxWidth: .infinity, alignment: .top) }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - A video tile

struct LibraryVideoTile: View {
    let video: LibraryVideo
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [FAColor.forest, FAColor.forestDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.95)).accessibilityHidden(true)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                Text(video.title).font(FATypography.display(13, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(LibraryVideoCopy.source(video))
                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2))
                    .foregroundStyle(video.isYouTube ? Color(hex: 0xB91C1C) : FAColor.forestSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(video.title). \(LibraryVideoCopy.source(video)). \(String(localized: "library.video.a11y", defaultValue: "Video"))")
        .accessibilityHint(String(localized: "library.video.hint", defaultValue: "Plays in the app"))
    }
}

enum LibraryVideoCopy {
    static func source(_ video: LibraryVideo) -> String {
        video.isYouTube ? String(localized: "library.video.youtube", defaultValue: "YouTube") : String(localized: "library.video.own", defaultValue: "FunctionAlps")
    }
}

// MARK: - The soft-lock sheet ("Opens on day N")

/// A day (or one read) still to come: it shows, it does not open.
struct LibrarySoftLock: Identifiable, Equatable {
    let day: Int
    let titles: [String]
    var id: Int { day }
}

struct LibrarySoftLockSheet: View {
    let lock: LibrarySoftLock
    let today: Int?
    let dayTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            let eyebrow = [String(localized: "library.day.n", defaultValue: "Day \(lock.day)"), dayTitle].compactMap { $0 }.joined(separator: " · ")
            Text(eyebrow.uppercased()).font(FATypography.sans(10, .bold, relativeTo: .caption)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                ForEach(lock.titles, id: \.self) { title in
                    Text(title).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.charcoal).multilineTextAlignment(.center)
                }
            }
            .accessibilityAddTraits(.isHeader)
            Text(LibrarySoftLockCopy.body(day: lock.day, today: today))
                .font(FATypography.sans(13.5, relativeTo: .body)).foregroundStyle(Color(hex: 0x4A4A42))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            Button { dismiss() } label: {
                Text(LibrarySoftLockCopy.button(day: lock.day, today: today))
                    .font(FATypography.sans(14, .bold, relativeTo: .body)).foregroundStyle(FAColor.cream)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(FAColor.forest, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(FAColor.warm)
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(FAColor.warm)
    }
}

enum LibrarySoftLockCopy {
    static func body(day: Int, today: Int?) -> String {
        let away = day - (today ?? day)
        if away == 1 {
            return String(localized: "library.soft.body.tomorrow", defaultValue: "This one opens on day \(day), tomorrow. One day at a time: each read lands on the day it belongs to.")
        }
        if away > 1 {
            return String(localized: "library.soft.body.later", defaultValue: "This one opens on day \(day), in \(away) days. One day at a time: each read lands on the day it belongs to.")
        }
        return String(localized: "library.soft.body.plain", defaultValue: "This one opens on day \(day). One day at a time: each read lands on the day it belongs to.")
    }

    static func button(day: Int, today: Int?) -> String {
        day - (today ?? day) == 1
            ? String(localized: "library.soft.ok.tomorrow", defaultValue: "OK, tomorrow")
            : String(localized: "library.soft.ok", defaultValue: "OK")
    }
}

// MARK: - Search results (topics first, then articles, habits, videos)

struct LibrarySearchResultsView: View {
    let query: String
    let results: LibrarySearch.Results
    let today: Int?
    let onTopic: (LibrarySearch.Topic) -> Void
    let onArticle: (LibraryArticle) -> Void
    let onHabit: (LibraryHabit) -> Void
    let onVideo: (LibraryVideo) -> Void

    var body: some View {
        if results.isEmpty {
            FAEmptyState(title: String(localized: "library.search.none", defaultValue: "No results"),
                         message: String(localized: "library.search.noneMessage", defaultValue: "Try another word."),
                         systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !results.topics.isEmpty {
                    LibrarySectionHead(title: String(localized: "library.search.topics", defaultValue: "Topics"))
                    FlowLayout(spacing: 7) {
                        ForEach(results.topics) { topic in
                            Button { onTopic(topic) } label: {
                                Text(topic.name).font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(FAColor.forest.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 18)
                }
                if !results.articles.isEmpty {
                    LibrarySectionHead(title: String(localized: "library.search.articles", defaultValue: "Articles"), note: "\(results.articles.count)")
                    LibraryReadGrid(items: results.articles) { article in
                        LibraryReadCard(kicker: kicker(article), title: article.title, lockedDay: FoundationLibraryLogic.opensOn(article, today: today)) { onArticle(article) }
                    }
                    .padding(.bottom, 18)
                }
                if !results.habits.isEmpty {
                    LibrarySectionHead(title: String(localized: "library.search.habits", defaultValue: "Habits"), note: "\(results.habits.count)")
                    VStack(spacing: 8) {
                        ForEach(results.habits) { habit in
                            Button { onHabit(habit) } label: {
                                FACard(padded: false) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(habit.title).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                                            Text([habit.moment?.label, String(localized: "library.practice.inActions", defaultValue: "in your actions")].compactMap { $0 }.joined(separator: " · "))
                                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted).accessibilityHidden(true)
                                    }
                                    .padding(12)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 18)
                }
                if !results.videos.isEmpty {
                    LibrarySectionHead(title: String(localized: "library.search.videos", defaultValue: "Videos"), note: "\(results.videos.count)")
                    LibraryReadGrid(items: results.videos) { video in LibraryVideoTile(video: video) { onVideo(video) } }
                }
            }
        }
    }

    private func kicker(_ article: LibraryArticle) -> String? {
        var parts: [String] = []
        if let topic = article.topic { parts.append(topic) }
        if let minutes = article.minutes { parts.append(String(localized: "library.minutes", defaultValue: "\(minutes) min")) }
        if let day = article.day, article.isFoundationTrack { parts.append(String(localized: "library.day.n", defaultValue: "Day \(day)")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
