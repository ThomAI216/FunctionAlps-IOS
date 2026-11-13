import SwiftUI
import UIKit

/// Food › Groceries: the plan week's shopping by aisle in store order, with ticks saved to the member's grocery state
/// (the same ticks as on the web) and a share button.
struct GroceriesView: View {
    @Bindable var plan: MealPlanViewModel

    var body: some View {
        switch plan.groceries {
        case .loading:
            FALoadingState().frame(height: 240)
        case .failed(let error):
            FAErrorState(title: String(localized: "grocery.error.title", defaultValue: "Couldn't load your groceries"), message: error.userMessage) {
                Task { await plan.loadGroceries() }
            }
            .frame(height: 280)
        case .empty:
            FAEmptyState(
                title: String(localized: "grocery.empty.title", defaultValue: "No grocery list yet"),
                message: String(localized: "grocery.empty.message", defaultValue: "Your grocery list is built from your meal plan. It appears once your practitioner shares one."),
                systemImage: "cart"
            )
            .padding(.vertical, 40)
        case .loaded(let list):
            content(list)
        }
    }

    private func content(_ list: GroceryList) -> some View {
        let counts = GroceryLogic.counts(list)
        return VStack(alignment: .leading, spacing: 14) {
            header(list, counts: counts)
            ForEach(list.aisles) { aisle in
                FACard {
                    VStack(alignment: .leading, spacing: 4) {
                        TrendLabel(text: aisle.label)
                        ForEach(aisle.items) { item in row(item) }
                    }
                }
            }
            if !list.custom.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 4) {
                        TrendLabel(text: String(localized: "grocery.own", defaultValue: "Your own items"))
                        ForEach(list.custom) { item in customRow(item) }
                    }
                }
            }
        }
    }

    private func header(_ list: GroceryList, counts: GroceryLogic.Counts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "grocery.title", defaultValue: "Your groceries")).font(FATypography.title).foregroundStyle(FAColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let period = GroceryLogic.periodLabel(start: list.periodStart, end: list.periodEnd) {
                        Text(String(localized: "grocery.period", defaultValue: "\(period) · from your plan"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                Spacer()
                Button { plan.showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.brand)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "grocery.share", defaultValue: "Save or share the list"))
            }
            ProgressView(value: Double(counts.inBasket), total: Double(max(counts.total, 1)))
                .tint(FAColor.forestSoft)
                .accessibilityHidden(true)
            Text(String(localized: "grocery.progress", defaultValue: "\(counts.inBasket) of \(counts.total) in the basket"))
                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }
    }

    private func row(_ item: GroceryItem) -> some View {
        let done = item.checked || item.have
        return HStack(spacing: 6) {
            FACheck(done: done, title: item.name) { plan.toggle(.food(item.foodItemId), checked: !item.checked) }
                .disabled(item.have)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(FATypography.body).strikethrough(done).foregroundStyle(FAColor.ink)
                if let context = GroceryLogic.context(item) {
                    Text(context).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                if item.have {
                    Text(String(localized: "grocery.have", defaultValue: "You have this")).font(FATypography.caption).foregroundStyle(FAColor.forestSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(GroceryLogic.quantityLabel(item)).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
        }
        .opacity(done ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private func customRow(_ item: GroceryCustomItem) -> some View {
        HStack(spacing: 6) {
            FACheck(done: item.checked, title: item.label) { plan.toggle(.custom(item.id), checked: !item.checked) }
            Text(item.label).font(FATypography.body).strikethrough(item.checked).foregroundStyle(FAColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let qty = item.qtyText?.nilIfEmpty {
                Text(qty).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
            }
        }
        .opacity(item.checked ? 0.55 : 1)
    }
}

/// What the share sheet hands over.
private struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// "Save or share your list": Still to buy / Whole list, then the iPhone share sheet as text (Notes, Reminders,
/// Messages, Mail), a PDF with tick boxes, or a plain copy. No Reminders permission: the share sheet needs none.
struct GrocerySaveShareSheet: View {
    let list: GroceryList
    let onDone: () -> Void

    @State private var scope: GroceryShareScope = .stillToBuy
    @State private var shareItems: ShareItems?
    @State private var copied = false
    @State private var pdfFailed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "grocery.save.title", defaultValue: "Save or share your list")).font(FATypography.title).foregroundStyle(FAColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(String(localized: "action.done", defaultValue: "Done"), action: onDone)
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.brand).frame(minHeight: 44)
                }
                FASegmentedControl(options: GroceryShareScope.allCases, selection: scope, title: label) { scope = $0 }
                preview
                action(title: String(localized: "grocery.save.text", defaultValue: "Share as text"),
                       detail: String(localized: "grocery.save.text.detail", defaultValue: "Opens the iPhone share sheet. Pick Notes to keep it as a note, or Reminders, Messages or Mail."),
                       icon: "square.and.arrow.up") { shareItems = ShareItems(items: [textValue]) }
                action(title: String(localized: "grocery.save.pdf", defaultValue: "Save as PDF"),
                       detail: String(localized: "grocery.save.pdf.detail", defaultValue: "Grouped by aisle, with tick boxes. Keep it in Files or print it."),
                       icon: "doc.richtext") { sharePDF() }
                action(title: copied ? String(localized: "grocery.save.copied", defaultValue: "Copied") : String(localized: "grocery.save.copy", defaultValue: "Copy"),
                       detail: String(localized: "grocery.save.copy.detail", defaultValue: "The list as plain text, ready to paste anywhere."),
                       icon: "doc.on.doc") {
                    UIPasteboard.general.string = textValue
                    copied = true
                }
                if pdfFailed {
                    Text(String(localized: "grocery.save.pdf.failed", defaultValue: "Couldn't create the PDF. Try again.")).font(FATypography.caption).foregroundStyle(FAColor.danger)
                }
                Text(String(localized: "grocery.save.note", defaultValue: "A shared copy is a snapshot. Ticks you make in Notes or Reminders stay there, and a later swap in your plan changes the list here, not the copy."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
            .padding(18)
        }
        .faWall()
        .onChange(of: scope) { _, _ in copied = false }
        .sheet(item: $shareItems) { ShareSheet(items: $0.items).presentationDetents([.medium, .large]) }
    }

    private func label(_ s: GroceryShareScope) -> String {
        let count = GroceryLogic.lineCount(list, scope: s)
        switch s {
        case .stillToBuy: return String(localized: "grocery.scope.left", defaultValue: "Still to buy · \(count)")
        case .whole: return String(localized: "grocery.scope.whole", defaultValue: "Whole list · \(count)")
        }
    }

    private var title: String {
        let base = String(localized: "grocery.share.title", defaultValue: "Groceries")
        if let period = GroceryLogic.periodLabel(start: list.periodStart, end: list.periodEnd) { return "\(base) · \(period)" }
        return base
    }

    private var textValue: String { GroceryLogic.text(list, scope: scope, title: title) }

    private var preview: some View {
        let sections = GroceryLogic.sections(list, scope: scope)
        return FACard {
            VStack(alignment: .leading, spacing: 6) {
                TrendLabel(text: String(localized: "grocery.save.preview", defaultValue: "What gets shared"))
                Text(title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                if sections.isEmpty {
                    Text(String(localized: "grocery.save.nothing", defaultValue: "Nothing left to buy.")).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                ForEach(Array(sections.prefix(2).enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title.uppercased()).font(FATypography.label).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                        ForEach(Array(section.lines.prefix(4).enumerated()), id: \.offset) { _, line in
                            Text(line).font(FATypography.callout).foregroundStyle(FAColor.ink)
                        }
                    }
                }
                if sections.count > 2 {
                    Text(String(localized: "grocery.save.more", defaultValue: "… and the other aisles, in shop order")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }

    private func action(title: String, detail: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            FACard {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.brand).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(GroceryLogic.lineCount(list, scope: scope) == 0)
    }

    private func sharePDF() {
        let sections = GroceryLogic.sections(list, scope: scope)
        let subtitle = GroceryLogic.periodLabel(start: list.periodStart, end: list.periodEnd)
        let data = GroceryPDF.render(sections: sections, title: String(localized: "grocery.share.title", defaultValue: "Groceries"), subtitle: subtitle)
        do {
            let url = try GroceryPDF.writeTemporaryFile(data, name: "functionalps-groceries-\(list.periodStart ?? "list").pdf")
            pdfFailed = false
            shareItems = ShareItems(items: [url])
        } catch {
            pdfFailed = true
        }
    }
}
