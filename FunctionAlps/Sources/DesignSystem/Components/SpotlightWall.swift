import SwiftUI
import UIKit

/// A wall (`lib/theme/walls.ts`): base gradient, a cool spotlight bleeding in from the top-right,
/// a warm glow rising from the bottom-left, and the dense dot grid (11 pt cells, 1.1 pt dots).
struct WallDef: Sendable, Equatable {
    struct Glow: Sendable, Equatable {
        let hex: UInt32
        let opacity: Double
    }
    let key: String
    let baseStart: UInt32
    let baseEnd: UInt32
    let top: Glow
    let bottom: Glow
    let dot: Glow
}

enum FAWalls {
    /// The owner's reference look (dd9).
    static let sage = WallDef(key: "dd9", baseStart: 0xE7F2E9, baseEnd: 0xBDDAC8, top: .init(hex: 0xFFFFFF, opacity: 0.95), bottom: .init(hex: 0x4A8A5C, opacity: 0.38), dot: .init(hex: 0x2E5438, opacity: 0.22))
    static let cream = WallDef(key: "dd7", baseStart: 0xF7EEDC, baseEnd: 0xE0CFA9, top: .init(hex: 0xFFFFFF, opacity: 0.95), bottom: .init(hex: 0xBFD8C7, opacity: 0.9), dot: .init(hex: 0x2E5438, opacity: 0.24))
    static let mist = WallDef(key: "dd10", baseStart: 0xE6EEF7, baseEnd: 0xBCD0E4, top: .init(hex: 0xFFFFFF, opacity: 0.95), bottom: .init(hex: 0x2B4A6E, opacity: 0.34), dot: .init(hex: 0x2B4A6E, opacity: 0.26))
    static let honey = WallDef(key: "dd8", baseStart: 0xFAF2E0, baseEnd: 0xE9CF98, top: .init(hex: 0xFFFFFF, opacity: 0.95), bottom: .init(hex: 0xC48B35, opacity: 0.42), dot: .init(hex: 0x2E5438, opacity: 0.22))

    /// The light walls the Appearance picker offers (the dark family needs the dark palette — not ported).
    static let choices: [WallDef] = [sage, cream, honey, mist]
    /// `UserDefaults` key the picker writes and every wall reads.
    static let storageKey = "fa.wall"
    static let defaultKey = "dd9"

    static func wall(for key: String) -> WallDef { choices.first { $0.key == key } ?? sage }

    static func label(for key: String) -> String {
        switch key {
        case "dd7": String(localized: "wall.cream", defaultValue: "Cream")
        case "dd8": String(localized: "wall.honey", defaultValue: "Honey")
        case "dd10": String(localized: "wall.mist", defaultValue: "Mist")
        default: String(localized: "wall.sage", defaultValue: "Sage")
        }
    }
}

/// Renders a wall as the page background — vector, crisp at any size, no image asset.
struct SpotlightWallView: View {
    /// The member's pick from Settings → Appearance; the Sage reference look until they choose.
    @AppStorage(FAWalls.storageKey) private var wallKey: String = FAWalls.defaultKey
    private var wall: WallDef { FAWalls.wall(for: wallKey) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: wall.baseStart), Color(hex: wall.baseEnd)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.35, y: 1))
                glow(wall.top, center: UnitPoint(x: 0.8, y: -0.1), rx: 0.95 * w, ry: 0.7 * h)
                glow(wall.bottom, center: UnitPoint(x: 0.1, y: 1.1), rx: 0.85 * w, ry: 0.65 * h)
                Image(uiImage: DotTile.image(for: wall.dot))
                    .resizable(resizingMode: .tile)
            }
        }
        .background(Color(hex: wall.baseEnd)) // never a white flash under a slow layout
        .accessibilityHidden(true)
    }

    private func glow(_ g: WallDef.Glow, center: UnitPoint, rx: CGFloat, ry: CGFloat) -> some View {
        Rectangle()
            .fill(RadialGradient(colors: [Color(hex: g.hex, opacity: g.opacity), Color(hex: g.hex, opacity: 0)], center: center, startRadius: 0, endRadius: max(1, rx)))
            .scaleEffect(x: 1, y: rx > 0 ? ry / rx : 1, anchor: center)
    }
}

/// The dot grid as a tiny tiled bitmap (one 11×11 cell), so the wall costs nothing to draw.
enum DotTile {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    static func image(for dot: WallDef.Glow) -> UIImage {
        let key = "\(dot.hex)-\(dot.opacity)"
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 11, height: 11), format: format).image { ctx in
            UIColor(hex: dot.hex, alpha: dot.opacity).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 5.5 - 1.1, y: 5.5 - 1.1, width: 2.2, height: 2.2))
        }
        cache[key] = image
        return image
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Every content screen sits on the wall; the floating tab bar floats over it.
extension View {
    func faWall() -> some View {
        ZStack {
            SpotlightWallView().ignoresSafeArea()
            self
        }
    }
}
