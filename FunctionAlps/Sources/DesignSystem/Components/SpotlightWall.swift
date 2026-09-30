import ImageIO
import SwiftUI
import UIKit

/// App walls are the owner's photos (2026-09-30: Blue 1, Blue 3, Sand 1, Sand 4 kept of the eleven
/// uploaded; the gradient "spotlight" walls are retired). Settings → Appearance picks one.
enum FAWalls {
    /// `UserDefaults` key the picker writes and every wall reads (`.v2` since the photo walls).
    static let storageKey = "fa.wall.v2"
    /// Owner testing: until the owner names the default photo, the first launch draws one at random and
    /// stores it, so it holds on every later launch until changed. A stored key for a photo that is no
    /// longer offered is redrawn the same way.
    static let defaultKey: String = {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: FAWalls.storageKey), FAPhotoWalls.photo(for: stored) != nil { return stored }
        let key = (FAPhotoWalls.all.randomElement() ?? FAPhotoWalls.all[0]).key
        defaults.set(key, forKey: FAWalls.storageKey)
        return key
    }()

    /// The photo for a stored key; anything unknown shows the default.
    static func resolved(_ key: String) -> PhotoWall {
        FAPhotoWalls.photo(for: key) ?? FAPhotoWalls.photo(for: defaultKey) ?? FAPhotoWalls.all[0]
    }
}

/// A photo wall: one of the owner's backgrounds, shipped as `Resources/Media/<file>.jpg`
/// (full-size originals kept in `design/backgrounds/`).
struct PhotoWall: Sendable, Equatable {
    enum Family: Sendable { case blue, sand }
    let file: String
    let family: Family
    /// The number the owner chose it by (the upload order within its colour), kept so names stay stable.
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
        .init(file: "bg-blue-3", family: .blue, number: 3, tint: 0x8FB2CA),
        .init(file: "bg-sand-1", family: .sand, number: 1, tint: 0xC0A78C),
        .init(file: "bg-sand-4", family: .sand, number: 4, tint: 0xA58E77),
    ]

    /// The photo a stored key shows, or nil when that key is not offered.
    static func photo(for key: String) -> PhotoWall? { all.first { $0.key == key } }

    /// A white wash over the photo so ink text on the wall keeps its contrast over the darker folds.
    static let veilOpacity = 0.28
}

/// Renders the member's wall as the page background.
struct SpotlightWallView: View {
    /// The member's pick from Settings → Appearance; until then, the photo drawn at first launch.
    @AppStorage(FAWalls.storageKey) private var wallKey: String = FAWalls.defaultKey

    var body: some View {
        PhotoWallView(photo: FAWalls.resolved(wallKey))
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
/// downsampled by ImageIO so the Appearance picker never decodes the full-size photos.
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

/// Every content screen sits on the wall; the floating tab bar floats over it.
extension View {
    func faWall() -> some View {
        ZStack {
            SpotlightWallView().ignoresSafeArea()
            self
        }
    }
}
