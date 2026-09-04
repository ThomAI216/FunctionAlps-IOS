import SwiftUI

/// Help & FAQ (the Expo `profile-help.tsx`): search, three categories of expandable questions,
/// and the green "Still need help?" card into Messages.
struct HelpView: View {
    @Environment(AppRouter.self) private var router
    @State private var search = ""
    @State private var open: Set<String> = []

    private var filtered: [FAQCategory] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count > 1 else { return FAQCategory.all }
        return FAQCategory.all.compactMap { cat in
            let items = cat.items.filter { $0.question.lowercased().contains(q) || $0.answer.lowercased().contains(q) }
            return items.isEmpty ? nil : FAQCategory(id: cat.id, symbol: cat.symbol, title: cat.title, items: items)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: String(localized: "settings.help", defaultValue: "Help & FAQ"))

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(ProfilePalette.muted)
                    TextField(String(localized: "help.search", defaultValue: "Search questions..."), text: $search)
                        .font(FATypography.sans(16, relativeTo: .body)).foregroundStyle(FAColor.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(search.isEmpty ? ProfilePalette.hairline : FAColor.forestSoft, lineWidth: 1.5) }
                .padding(.top, 6).padding(.bottom, 20)

                ForEach(filtered) { cat in
                    SurfaceCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x4A8A5C, opacity: 0.13))
                                    Image(systemName: cat.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                }
                                .frame(width: 32, height: 32)
                                Text(cat.title).font(FATypography.sans(15, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            }
                            .padding(.bottom, 4)
                            ForEach(Array(cat.items.enumerated()), id: \.element.id) { i, item in
                                let key = cat.id + "/" + item.id
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if open.contains(key) { open.remove(key) } else { open.insert(key) }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(item.question).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: open.contains(key) ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                                        }
                                        if open.contains(key) {
                                            Text(item.answer).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                                        }
                                    }
                                    .multilineTextAlignment(.leading)
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .bottom) {
                                    if i < cat.items.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 14)
                }

                if filtered.isEmpty {
                    Text(String(localized: "help.noResults", defaultValue: "No results for \"\(search)\""))
                        .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }

                Button { router.profilePath.append(.messages) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FAColor.cream.opacity(0.18))
                            Image(systemName: "bubble.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.cream)
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(localized: "help.stillNeed", defaultValue: "Still need help?")).font(FATypography.sans(14, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.cream)
                            Text(String(localized: "help.stillNeed.sub", defaultValue: "Send a message to your nutritionist")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.cream.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(LinearGradient(colors: [FAColor.forestSoft, FAColor.forest], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}
