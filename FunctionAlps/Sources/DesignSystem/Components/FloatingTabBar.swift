import SwiftUI

/// The web app's floating 5-tab pill: see-through frosted glass, black icons, DM Sans labels.
struct FloatingTabBar: View {
    @Binding var selection: AppRouter.Tab
    /// A small count on a tab (the Library: items the practice sent, not yet opened). 0 or absent = nothing.
    var badges: [AppRouter.Tab: Int] = [:]
    /// Tabs the Foundation Track keeps locked for now: a small lock on the icon (the tab still opens, on its lock).
    var locked: Set<AppRouter.Tab> = []

    private struct Item: Identifiable {
        let tab: AppRouter.Tab
        let label: String
        let symbol: String
        var id: AppRouter.Tab { tab }
    }

    private var items: [Item] {
        [
            Item(tab: .home, label: String(localized: "tab.home", defaultValue: "Home"), symbol: "house"),
            Item(tab: .trends, label: String(localized: "tab.trends", defaultValue: "Trends"), symbol: "chart.line.uptrend.xyaxis"),
            Item(tab: .food, label: String(localized: "tab.food", defaultValue: "Food"), symbol: "fork.knife"),
            Item(tab: .library, label: String(localized: "tab.library", defaultValue: "Library"), symbol: "book"),
            Item(tab: .profile, label: String(localized: "tab.profile", defaultValue: "Profile"), symbol: "person"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let focused = selection == item.tab
                Button {
                    if selection != item.tab {
                        selection = item.tab
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 22, weight: focused ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if locked.contains(item.tab) {
                                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 16, height: 16).background(FAColor.charcoal.opacity(0.7), in: Circle())
                                        .offset(x: 10, y: -6)
                                        .accessibilityHidden(true)
                                } else if let n = badges[item.tab], n > 0 {
                                    Text("\(n)")
                                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                        .background(FAColor.forestSoft, in: Capsule())
                                        .offset(x: 10, y: -6)
                                        .accessibilityLabel(String(localized: "tab.badge", defaultValue: "\(n) new"))
                                }
                            }
                        Text(item.label)
                            .font(FATypography.sans(9.5, .semibold, relativeTo: .caption2))
                    }
                    .foregroundStyle(focused ? FAColor.charcoal : FAColor.charcoal.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(locked.contains(item.tab)
                                    ? String(localized: "tab.locked", defaultValue: "\(item.label), locked") : item.label)
                .accessibilityAddTraits(focused ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 66)
        .modifier(FATabBarGlass())
        .padding(.horizontal, 16)
    }
}

/// The pill's glass: the same see-through glass as `FACard` (clear Liquid Glass on iOS 26, the
/// web's frosted white recipe before it) — never the tinted/regular variant, which iOS 26 renders
/// as an opaque grey slab over the Sage wall.
private struct FATabBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear.interactive(), in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        } else {
            content
                .background(Color.white.opacity(0.20), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1) }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        }
    }
}
