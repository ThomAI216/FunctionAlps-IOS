import SwiftUI

// The DETECTED ITEMS list (the Expo `EditableItemList`): editable rows (name · − grams + · ×), "Add item", the
// amber clarification chips, and the gram wheel. ONE LIST, several bindings — the describe card, the capture
// screen's "tell us what you ate" card, the photo review and the post-analysis editor all render THIS, never a
// lookalike. A row that must look different gets a prop here, not a copy of this file.

/// One editable row, in whatever vocabulary the caller's model speaks.
struct EditableRow: Identifiable, Equatable {
    let id: Int
    var name: String
    var grams: Double
    /// A quiet second line under the name (kcal, "not counted", …).
    var note: String? = nil
    /// Ring the row: there is an open question about it, or the resolver could not identify it.
    var flagged = false
}

/// One amber question about one row. `label` is what the member reads; `value` is what the handler receives.
struct RowQuestion: Identifiable {
    struct Option: Identifiable { let label: String; let value: String; var id: String { value } }
    let id: String
    let itemIndex: Int
    let question: String
    let options: [Option]
    let onPick: (String) -> Void
    let onDismiss: () -> Void
}

struct EditableItemList<UnderRow: View>: View {
    let items: [EditableRow]
    var questions: [RowQuestion] = []
    let onRename: (Int, String) -> Void
    let onGrams: (Int, Double) -> Void
    let onRemove: (Int) -> Void
    var onAdd: ((String) -> Void)? = nil
    var addLabel: String? = nil
    /// Anything the caller wants directly under a row — the photo review's reference portions live here.
    @ViewBuilder var underRow: (Int) -> UnderRow

    @State private var adding = false
    @State private var newName = ""
    @State private var wheel: Int?
    @FocusState private var addFocused: Bool

    init(items: [EditableRow], questions: [RowQuestion] = [], onRename: @escaping (Int, String) -> Void, onGrams: @escaping (Int, Double) -> Void, onRemove: @escaping (Int) -> Void, onAdd: ((String) -> Void)? = nil, addLabel: String? = nil, @ViewBuilder underRow: @escaping (Int) -> UnderRow) {
        self.items = items
        self.questions = questions
        self.onRename = onRename
        self.onGrams = onGrams
        self.onRemove = onRemove
        self.onAdd = onAdd
        self.addLabel = addLabel
        self.underRow = underRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 0) {
                    row(item)
                    underRow(item.id)
                }
            }
            if onAdd != nil { addRow }
            if !questions.isEmpty {
                VStack(spacing: 8) { ForEach(questions) { questionCard($0) } }.padding(.top, 4)
            }
        }
        .sheet(item: Binding(get: { wheel.map(WheelTarget.init) }, set: { wheel = $0?.index })) { target in
            if let item = items.first(where: { $0.id == target.index }) {
                GramWheel(value: item.grams, title: Self.capFirst(item.name)) { onGrams(item.id, $0) }
            }
        }
    }

    private struct WheelTarget: Identifiable { let index: Int; var id: Int { index } }

    private func row(_ item: EditableRow) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                TextField(String(localized: "food.item.placeholder", defaultValue: "Food"), text: Binding(get: { Self.capFirst(item.name) }, set: { onRename(item.id, $0) }))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption))
                    .foregroundStyle(FAColor.ink)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                if let note = item.note {
                    Text(note).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FoodPalette.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                nudge("minus") { onGrams(item.id, MealEdit.nudged(item.grams, direction: -1)) }
                Button { wheel = item.id } label: {
                    (Text("\(Int(item.grams.rounded()))").font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundColor(FAColor.ink)
                        + Text(" g").font(FATypography.sans(10, relativeTo: .caption2)).foregroundColor(FoodPalette.muted))
                        .frame(minWidth: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "food.item.grams.a11y", defaultValue: "\(Int(item.grams.rounded())) grams, tap to change"))
                nudge("plus") { onGrams(item.id, MealEdit.nudged(item.grams, direction: 1)) }
                Button { onRemove(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(FoodPalette.muted).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "food.item.remove", defaultValue: "Remove \(item.name)"))
            }
        }
        .padding(.vertical, 6).padding(.leading, 10).padding(.trailing, 8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(item.flagged ? FAColor.goldSoft.opacity(0.7) : FoodPalette.hairline, lineWidth: 1) }
    }

    private func nudge(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                .frame(width: 22, height: 22)
                .background(FoodPalette.surfaceSoft, in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var addRow: some View {
        if adding {
            HStack(spacing: 8) {
                TextField(String(localized: "food.item.addPlaceholder", defaultValue: "Food item…"), text: $newName)
                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    .focused($addFocused)
                    .onSubmit(commitAdd)
                    .overlay(alignment: .bottom) { Rectangle().fill(FAColor.forestSoft).frame(height: 1).offset(y: 4) }
                Button(String(localized: "action.add", defaultValue: "Add"), action: commitAdd)
                    .font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft).buttonStyle(.plain)
                Button { adding = false; newName = "" } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(FoodPalette.muted) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.top, 2)
            .onAppear { addFocused = true }
        } else {
            Button { adding = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text(addLabel ?? String(localized: "food.item.add", defaultValue: "Add item")).font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
                }
                .foregroundStyle(FAColor.forestSoft)
                .padding(.vertical, 3).padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitAdd() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        onAdd?(n)
        newName = ""
        adding = false
    }

    private func questionCard(_ q: RowQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.forestSoft).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    if let target = items.first(where: { $0.id == q.itemIndex }) {
                        Text(String(localized: "food.clarify.about", defaultValue: "About “\(target.name)”").uppercased())
                            .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.5).foregroundStyle(Color(hex: 0xB8860B))
                    }
                    Text(q.question).font(FATypography.sans(11.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                }
                Spacer(minLength: 4)
                Button(action: q.onDismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(FoodPalette.muted) }
                    .buttonStyle(.plain)
            }
            FlowLayout(spacing: 6) {
                ForEach(q.options) { opt in
                    Button { q.onPick(opt.value) } label: {
                        Text(opt.label).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.7), in: Capsule())
                            .overlay { Capsule().strokeBorder(FAColor.goldSoft.opacity(0.5), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
                Button(action: q.onDismiss) {
                    Text(String(localized: "food.clarify.keep", defaultValue: "Keep as is")).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FoodPalette.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay { Capsule().strokeBorder(FoodPalette.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(FAColor.goldSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FAColor.goldSoft.opacity(0.45), lineWidth: 1) }
    }

    /// Item names come back lowercase; the first letter is capitalised for display.
    static func capFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

extension EditableItemList where UnderRow == EmptyView {
    init(items: [EditableRow], questions: [RowQuestion] = [], onRename: @escaping (Int, String) -> Void, onGrams: @escaping (Int, Double) -> Void, onRemove: @escaping (Int) -> Void, onAdd: ((String) -> Void)? = nil, addLabel: String? = nil) {
        self.init(items: items, questions: questions, onRename: onRename, onGrams: onGrams, onRemove: onRemove, onAdd: onAdd, addLabel: addLabel) { _ in EmptyView() }
    }
}

/// A spin-wheel gram picker (5–1500 g in 5 g steps), committed on Done.
struct GramWheel: View {
    let value: Double
    let title: String
    let onSelect: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(value: Double, title: String, onSelect: @escaping (Double) -> Void) {
        self.value = value
        self.title = title
        self.onSelect = onSelect
        _selection = State(initialValue: max(5, min(1500, Int((value / 5).rounded()) * 5)))
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title.isEmpty ? String(localized: "food.item.quantity", defaultValue: "Quantity") : title)
                .font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1).padding(.top, 16)
            Picker("", selection: $selection) {
                ForEach(Array(stride(from: 5, through: 1500, by: 5)), id: \.self) { g in
                    Text("\(g) g").tag(g)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 180)
            ForestPillButton(title: String(localized: "action.done", defaultValue: "Done")) {
                onSelect(Double(selection))
                dismiss()
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(320)])
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.light)
        .background { FAGlassSurfaceBox() }
    }
}

/// The glass slab behind a bottom sheet — the same recipe as every card, inset like the photo chooser.
private struct FAGlassSurfaceBox: View {
    var body: some View {
        Color.clear
            .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }
}
