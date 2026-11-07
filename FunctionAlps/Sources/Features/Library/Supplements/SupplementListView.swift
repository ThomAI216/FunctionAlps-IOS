import SwiftUI

/// The Supplements section of the Library (mockup phone 1): the intro, then one row per published supplement —
/// the visual, the one line, its uses as chips. Use rows never appear here on their own. Veiled until the
/// practitioner opens the section; empty when nothing is published yet.
struct SupplementListView: View {
    let pages: [LibResource]
    let usesByPage: [String: [LibResource]]
    let open: Bool
    let expanded: Bool
    let onToggle: () -> Void
    let onOpen: (LibResource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: String(localized: "library.section.supplements", defaultValue: "Supplements"), note: "\(pages.count)")
            Veiled(open: open) {
                VStack(alignment: .leading, spacing: 9) {
                    intro
                    if pages.isEmpty {
                        FACard {
                            FAEmptyState(title: String(localized: "supplement.list.empty.title", defaultValue: "No supplements published yet"),
                                         message: String(localized: "supplement.list.empty.message", defaultValue: "They appear here once your practice has reviewed the research."),
                                         systemImage: "pills")
                        }
                    } else {
                        ForEach(LibraryLogic.visibleItems(pages, expanded: expanded)) { page in
                            row(page)
                        }
                        MoreToggle(label: LibraryLogic.toggleLabel(total: pages.count, expanded: expanded, noun: String(localized: "library.noun.supplements", defaultValue: "supplements")), expanded: expanded, onPress: onToggle)
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "supplement.list.title", defaultValue: "A short selection we trust"))
                .font(FATypography.display(20, relativeTo: .title2)).foregroundStyle(FAColor.ink)
            Text(String(localized: "supplement.list.intro", defaultValue: "Food first, always. These are the ones we find useful most often. Talk to your nutritionist before you start anything new, especially if you take medication, are pregnant or breastfeeding."))
                .font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x33362F))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private func row(_ page: LibResource) -> some View {
        let uses = (usesByPage[page.slug] ?? []).map { SupplementLogic.useChip(title: $0.title, supplement: page.title) }
        return Button { onOpen(page) } label: {
            FACard(padded: false) {
                HStack(spacing: 10) {
                    SupplementVisualView(visual: page.supplementVisual, compact: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title).font(FATypography.display(16, relativeTo: .headline)).foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                        if !page.summary.isEmpty {
                            Text(page.summary).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                                .multilineTextAlignment(.leading).lineLimit(2)
                        }
                        if !uses.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(uses, id: \.self) { chip in
                                    Text(chip).font(FATypography.sans(9, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.forest)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(FAColor.forestSoft.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: page.locked ? "lock.fill" : "chevron.right")
                        .font(.system(size: page.locked ? 11 : 12, weight: .semibold))
                        .foregroundStyle(page.locked ? FALibraryColor.gold : FAColor.stone)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 11).padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(page, uses: uses))
    }

    private func accessibilityLabel(_ page: LibResource, uses: [String]) -> String {
        var parts = [page.title]
        if !page.summary.isEmpty { parts.append(page.summary) }
        if !uses.isEmpty { parts.append(uses.joined(separator: ", ")) }
        if page.locked { parts.append(String(localized: "library.locked", defaultValue: "Locked")) }
        return parts.joined(separator: ". ")
    }
}
