import SwiftUI

/// A periodic-table tile drawn by the app: number, symbol, name and (full size) mass, as the publisher wrote them.
/// The tint follows the element's group (alkali, halogen, the rest); the text carries the information.
struct ElementTile: View {
    let element: SupplementVisual.Element
    var compact = false

    private static let alkali: Set<Int> = [3, 11, 19, 37, 55, 87]
    private static let halogens: Set<Int> = [9, 17, 35, 53, 85]

    private var palette: (from: UInt32, to: UInt32, border: UInt32, ink: UInt32) {
        if Self.alkali.contains(element.number) { return (0xEEE9F8, 0xDCD3EF, 0x6E5B9A, 0x2B2240) }
        if Self.halogens.contains(element.number) { return (0xE3F2F3, 0xCBE6E8, 0x3C7A86, 0x13353A) }
        return (0xFBF1DC, 0xF2E0B8, 0x8C6A2C, 0x3B2A0E)
    }

    var body: some View {
        let p = palette
        let ink = Color(hex: p.ink)
        VStack(spacing: compact ? 1 : 2) {
            HStack {
                Text("\(element.number)").font(FATypography.sans(compact ? 7 : 10, .semibold, relativeTo: .caption2)).monospacedDigit()
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(element.symbol).font(FATypography.sans(compact ? 18 : 30, .bold, relativeTo: compact ? .headline : .title)).tracking(-0.5)
                .minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 0)
            Text(element.name).font(FATypography.sans(compact ? 6 : 8.5, .semibold, relativeTo: .caption2)).lineLimit(1).minimumScaleFactor(0.7)
            if !compact, let mass = element.mass {
                Text(mass).font(FATypography.sans(7.5, relativeTo: .caption2)).monospacedDigit().foregroundStyle(ink.opacity(0.75))
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, compact ? 4 : 6).padding(.top, compact ? 3 : 5).padding(.bottom, compact ? 4 : 6)
        .frame(width: compact ? 46 : 74, height: compact ? 52 : 82)
        .background(LinearGradient(colors: [Color(hex: p.from), Color(hex: p.to)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous).strokeBorder(Color(hex: p.border), lineWidth: 1.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "supplement.element.a11y", defaultValue: "\(element.name), element \(element.number), \(element.symbol)"))
    }
}

/// The visual by kind: one tile per element, or the molecule; nothing published → a quiet placeholder.
struct SupplementVisualView: View {
    let visual: SupplementVisual?
    var compact = false

    var body: some View {
        switch visual {
        case .elements(let elements):
            HStack(spacing: compact ? 4 : 6) {
                ForEach(Array(elements.prefix(compact ? 2 : 4).enumerated()), id: \.offset) { _, e in
                    ElementTile(element: e, compact: compact || elements.count > 1)
                }
            }
        case .molecule(let molecule):
            MoleculeView(molecule: molecule)
                .frame(width: compact ? 46 : 120, height: compact ? 52 : 82)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.25), lineWidth: 1) }
        case nil:
            Image(systemName: "pills")
                .font(.system(size: compact ? 16 : 24, weight: .medium))
                .foregroundStyle(FAColor.forest)
                .frame(width: compact ? 46 : 74, height: compact ? 52 : 82)
                .background(FAColor.forestSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
