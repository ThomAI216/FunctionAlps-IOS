import ImageIO
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
    /// `UserDefaults` key the picker writes and every wall reads. `.v2` so the photo walls reach
    /// members who picked a gradient before the photos shipped.
    static let storageKey = "fa.wall.v2"
    /// Owner testing (2026-09-30): until the owner names the default photo, the first launch draws one at
    /// random and stores it, so it holds on every later launch until changed in Settings → Appearance.
    static let defaultKey: String = {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: FAWalls.storageKey) { return stored }
        let key = (FAPhotoWalls.all.randomElement() ?? FAPhotoWalls.all[0]).key
        defaults.set(key, forKey: FAWalls.storageKey)
        return key
    }()

    static func wall(for key: String) -> WallDef { choices.first { $0.key == key } ?? sage }

    static func label(for key: String) -> String {
        if let photo = FAPhotoWalls.photo(for: key) { return photo.label }
        switch key {
        case "dd7": return String(localized: "wall.cream", defaultValue: "Cream")
        case "dd8": return String(localized: "wall.honey", defaultValue: "Honey")
        case "dd10": return String(localized: "wall.mist", defaultValue: "Mist")
        default: return String(localized: "wall.sage", defaultValue: "Sage")
        }
    }
}

/// A photo wall: one of the owner's backgrounds, shipped as `Resources/Media/<file>.jpg`
/// (full-size originals kept in `design/backgrounds/`).
struct PhotoWall: Sendable, Equatable {
    enum Family: Sendable { case blue, sand }
    let file: String
    let family: Family
    let number: Int
    /// The image's average colour — painted underneath so a slow decode never flashes white.
    let tint: UInt32

    var key: String { "photo.\(file)" }

    var label: String {
        switch family {
        case .blue: "\(String(localized: "wall.blue", defaultValue: "Blue")) \(number)"
        case .sand: "\(String(localized: "wall.sand", defaultValue: "Sand")) \(number)"
        }
    }
}

enum FAPhotoWalls {
    static let all: [PhotoWall] = [
        .init(file: "bg-blue-1", family: .blue, number: 1, tint: 0x91AEC6),
        .init(file: "bg-blue-2", family: .blue, number: 2, tint: 0x8BAFCC),
        .init(file: "bg-blue-3", family: .blue, number: 3, tint: 0x8FB2CA),
        .init(file: "bg-blue-4", family: .blue, number: 4, tint: 0x92B4CD),
        .init(file: "bg-sand-1", family: .sand, number: 1, tint: 0xC0A78C),
        .init(file: "bg-sand-2", family: .sand, number: 2, tint: 0xBAA68E),
        .init(file: "bg-sand-3", family: .sand, number: 3, tint: 0xA28D75),
        .init(file: "bg-sand-4", family: .sand, number: 4, tint: 0xA58E77),
        .init(file: "bg-sand-5", family: .sand, number: 5, tint: 0xA08A74),
        .init(file: "bg-sand-6", family: .sand, number: 6, tint: 0xAD9881),
        .init(file: "bg-sand-7", family: .sand, number: 7, tint: 0xB49D84),
    ]

    /// The photo a stored key shows, or nil for a gradient wall.
    static func photo(for key: String) -> PhotoWall? { all.first { $0.key == key } }

    /// A white wash over the photo so ink text on the wall keeps its contrast over the darker folds.
    static let veilOpacity = 0.28
}

/// Renders a wall as the page background: a photo wall, or a vector gradient wall (crisp at any size).
struct SpotlightWallView: View {
    /// The member's pick from Settings → Appearance; until then, the photo drawn at first launch.
    @AppStorage(FAWalls.storageKey) private var wallKey: String = FAWalls.defaultKey
    private var wall: WallDef { FAWalls.wall(for: wallKey) }

    var body: some View {
        if let photo = FAPhotoWalls.photo(for: wallKey) {
            PhotoWallView(photo: photo)
        } else {
            gradientWall
        }
    }

    private var gradientWall: some View {
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

struct PhotoWallView: View {
    let photo: PhotoWall

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = PhotoWallImages.full(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                Color.white.opacity(FAPhotoWalls.veilOpacity)
            }
        }
        .background(Color(hex: photo.tint))
        .accessibilityHidden(true)
    }
}

/// Decoded photo walls, kept once per file: every screen's wall reuses the same bitmap. Thumbnails are
/// downsampled by ImageIO so the Appearance picker never decodes eleven full-size photos.
enum PhotoWallImages {
    nonisolated(unsafe) private static var fullCache: [String: UIImage] = [:]
    nonisolated(unsafe) private static var thumbCache: [String: UIImage] = [:]

    static func full(_ photo: PhotoWall) -> UIImage? {
        if let cached = fullCache[photo.file] { return cached }
        guard let image = FAMedia.image(photo.file, ext: "jpg")?.preparingForDisplay() else { return nil }
        fullCache[photo.file] = image
        return image
    }

    static func thumbnail(_ photo: PhotoWall, maxPixel: Int = 180) -> UIImage? {
        if let cached = thumbCache[photo.file] { return cached }
        guard let url = Bundle.main.url(forResource: photo.file, withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        thumbCache[photo.file] = image
        return image
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
