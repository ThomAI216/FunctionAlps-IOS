import UIKit

/// Photos leave the phone downscaled and re-encoded (strips EXIF/location, ~200–400 KB),
/// matching the Expo picker's `quality: 0.6`.
enum MealImage {
    static let maxDimension: CGFloat = 1280
    static let quality: CGFloat = 0.6

    static func jpeg(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
