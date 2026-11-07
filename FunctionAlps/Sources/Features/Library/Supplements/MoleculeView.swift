import SwiftUI

/// A skeletal formula drawn natively from PubChem's 2D coordinates (no image, no network at reading time): bonds as
/// lines (double and triple as parallel lines), heteroatoms as their symbol, carbons as vertices. Scales with the
/// frame and the label with Dynamic Type.
struct MoleculeView: View {
    let molecule: SupplementVisual.Molecule
    var lineWidth: CGFloat = 1.8

    private static let labelTint: [String: UInt32] = ["N": 0x2B4FA0, "O": 0xB03030, "S": 0xA67C00, "P": 0xB05A1E, "Cl": 0x2E7D32, "F": 0x2E7D32, "Br": 0x7A3B1E, "I": 0x5B2A86]

    var body: some View {
        Canvas { context, size in
            let points = Self.fit(molecule.atoms, in: size, inset: 12)
            guard !points.isEmpty else { return }
            let bondColor = FAColor.charcoal
            for bond in molecule.bonds where bond.a < points.count && bond.b < points.count {
                let a = points[bond.a], b = points[bond.b]
                let labelledA = molecule.atoms[bond.a].element != "C", labelledB = molecule.atoms[bond.b].element != "C"
                // Leave room around a labelled atom so the symbol reads, not the line through it.
                let (start, end) = Self.trim(a, b, startInset: labelledA ? 7 : 0, endInset: labelledB ? 7 : 0)
                let dx = end.x - start.x, dy = end.y - start.y
                let length = max(0.001, (dx * dx + dy * dy).squareRoot())
                let normal = CGPoint(x: -dy / length * 3, y: dx / length * 3)
                let offsets: [CGFloat] = switch max(1, min(3, bond.order)) {
                case 2: [-1, 1]
                case 3: [-1, 0, 1]
                default: [0]
                }
                for k in offsets {
                    var path = Path()
                    path.move(to: CGPoint(x: start.x + normal.x * k, y: start.y + normal.y * k))
                    path.addLine(to: CGPoint(x: end.x + normal.x * k, y: end.y + normal.y * k))
                    context.stroke(path, with: .color(bondColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            for (i, atom) in molecule.atoms.enumerated() where atom.element != "C" {
                let tint = Color(hex: Self.labelTint[atom.element] ?? 0x1A1A16)
                let text = Text(atom.element).font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundColor(tint)
                let resolved = context.resolve(text)
                let box = resolved.measure(in: size)
                let rect = CGRect(x: points[i].x - box.width / 2 - 1, y: points[i].y - box.height / 2, width: box.width + 2, height: box.height)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(Color.white.opacity(0.9)))
                context.draw(resolved, at: points[i], anchor: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = molecule.name ?? molecule.formula ?? ""
        return name.isEmpty
            ? String(localized: "supplement.molecule.a11y.anon", defaultValue: "Molecule structure")
            : String(localized: "supplement.molecule.a11y", defaultValue: "\(name), molecule structure")
    }

    /// PubChem's y axis points up; the screen's points down. Scale to fit, keep the aspect, centre.
    static func fit(_ atoms: [SupplementVisual.Atom], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard let first = atoms.first else { return [] }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for a in atoms { minX = min(minX, a.x); maxX = max(maxX, a.x); minY = min(minY, a.y); maxY = max(maxY, a.y) }
        let w = max(maxX - minX, 0.001), h = max(maxY - minY, 0.001)
        let scale = min((size.width - inset * 2) / w, (size.height - inset * 2) / h)
        let drawnW = w * scale, drawnH = h * scale
        let ox = (size.width - drawnW) / 2, oy = (size.height - drawnH) / 2
        return atoms.map { a in
            CGPoint(x: ox + (a.x - minX) * scale, y: oy + (maxY - a.y) * scale)
        }
    }

    private static func trim(_ a: CGPoint, _ b: CGPoint, startInset: CGFloat, endInset: CGFloat) -> (CGPoint, CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > startInset + endInset + 1 else { return (a, b) }
        let ux = dx / length, uy = dy / length
        return (CGPoint(x: a.x + ux * startInset, y: a.y + uy * startInset), CGPoint(x: b.x - ux * endInset, y: b.y - uy * endInset))
    }
}
