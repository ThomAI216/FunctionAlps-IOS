import SwiftUI

// Small pieces shared by the client's care-plan screens (Today card, Plan, objective, Why, Situation, Journey).
// Everything is drawn small on purpose (owner, 2026-11-12): checks about 28 pt, buttons 34 pt, hit areas 44 pt.

enum ClientPlanFormat {
    /// "25 Nov" for a `YYYY-MM-DD` day, in the app's language; the raw text when it does not parse.
    static func shortDate(_ day: String) -> String {
        guard let date = HabitEngine.date(String(day.prefix(10))) else { return day }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    /// "Nov 2026" for a `YYYY-MM-DD` day.
    static func monthYear(_ day: String) -> String {
        guard let date = HabitEngine.date(String(day.prefix(10))) else { return day }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return f.string(from: date)
    }

    /// "Week 7 of 16", or "Week 7" when the length is unknown.
    static func weekText(_ week: Int, of total: Int?) -> String {
        guard let total else { return String(localized: "home.healthPlan.week", defaultValue: "Week \(week)") }
        return String(localized: "careplan.weekOf", defaultValue: "Week \(week) of \(total)")
    }
}

/// The small caps label above a block.
struct CPLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(FATypography.label).tracking(0.6).foregroundStyle(FAColor.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin progress bar; the figure beside it, not the colour, carries the number.
struct CPProgressBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FAColor.forestMist.opacity(0.7))
                Capsule().fill(FAColor.accent).frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// "Managed / Being taken care of / Not yet managed": symbol + words, small.
struct CPStatusPill: View {
    let status: ClientCarePlanLogic.ComplaintStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            Text(status.label).font(FATypography.sans(11, .semibold, relativeTo: .caption))
        }
        .foregroundStyle(status == .notYet ? FAColor.inkSecondary : FAColor.forestDark)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((status == .notYet ? FAColor.inkMuted : FAColor.forestSoft).opacity(0.16), in: Capsule())
    }
}

/// The small curve under a complaint: the check-in series the app already holds, 0…100. Decorative — the summary
/// line carries the meaning — so VoiceOver skips it.
struct MiniCurve: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            .stroke(FAColor.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                Circle().fill(FAColor.accent).frame(width: 5, height: 5).position(last)
            }
        }
        .frame(width: 64, height: 22)
        .accessibilityHidden(true)
    }

    /// Points for a series: oldest left, 100 at the top of the box. Pure, so it is testable.
    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 100
        let span = max(hi - lo, 20)   // a flat run stays flat, not stretched to the box
        let mid = (hi + lo) / 2
        return values.enumerated().map { index, v in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * (0.5 - CGFloat((v - mid) / span) * 0.9)
            return CGPoint(x: x, y: min(max(y, 2), size.height - 2))
        }
    }
}

/// The card's chevron row: a title and an optional detail that opens a screen. 44 pt tall at least.
struct CPLinkRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(FAColor.accent)
                    .frame(width: 28, height: 28).background(FAColor.accent.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The three-state wrapper the care-plan sub-screens share: loading → FALoadingState, failed → FAErrorState with a retry,
/// empty → FAEmptyState, loaded → the content. (Rule 5.)
struct ClientPlanScaffold<Content: View>: View {
    @Environment(AppDependencies.self) private var dependencies
    let title: String
    @ViewBuilder let content: (ClientCarePlanRaw) -> Content

    var body: some View {
        let service = dependencies.clientPlan
        VStack(spacing: 0) {
            CenteredHeader(title: title, hairline: true)
            switch service.state {
            case .loading:
                FALoadingState(message: String(localized: "careplan.loading", defaultValue: "Loading your plan…"))
            case .failed(let error):
                FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"), message: error.userMessage) {
                    Task { await service.load(force: true) }
                }
            case .empty:
                FAEmptyState(title: String(localized: "careplan.empty.title", defaultValue: "Nothing shared yet"),
                             message: String(localized: "careplan.empty.message", defaultValue: "Your practitioner will share your plan here."))
                    .frame(maxHeight: .infinity)
            case .loaded(let raw):
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) { content(raw) }
                        .padding(16)
                        .padding(.bottom, FASpacing.navBarClearance)
                }
                .refreshable { await service.load(force: true) }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await service.load() }
    }
}
