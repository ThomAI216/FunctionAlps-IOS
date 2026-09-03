import SwiftUI

/// The web app's floating 5-tab pill: see-through frosted glass, black icons, DM Sans labels.
struct FloatingTabBar: View {
    @Binding var selection: AppRouter.Tab

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
                        Text(item.label)
                            .font(FATypography.sans(9.5, .semibold, relativeTo: .caption2))
                    }
                    .foregroundStyle(focused ? FAColor.charcoal : FAColor.charcoal.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
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
