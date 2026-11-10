import Foundation

/// The Bristol Stool Form Scale chart bundled as `Media/bristol-chart.jpg`: the seven-row table and its
/// attribution, cropped from the Norgine chart the owner supplied (2026-11-10). The attribution is part of the
/// image and must stay in it (THIRD_PARTY_NOTICES.md).
///
/// The rows' borders, as fractions of the image height (top → bottom), measured on the crop — the chart is
/// tappable, so a tap on a row answers that type.
enum BristolChart {
    static let imageName = "bristol-chart"
    static let imageExt = "jpg"
    /// Width ÷ height of the bundled crop (1200 × 1584).
    static let aspectRatio = 1200.0 / 1584.0

    /// Eight borders → seven rows; below the last one is the attribution.
    static let rowBorders: [Double] = [0.0059, 0.1373, 0.2687, 0.3986, 0.5266, 0.6545, 0.7820, 0.9099]

    static let types = 1...7

    /// The vertical span of a type's row, as fractions of the image height; nil outside 1–7.
    static func rowRange(_ type: Int) -> ClosedRange<Double>? {
        guard types.contains(type) else { return nil }
        return rowBorders[type - 1]...rowBorders[type]
    }

    /// The type whose row holds a tap at `fraction` of the image height; nil above the table or on the
    /// attribution below it.
    static func type(atFraction fraction: Double) -> Int? {
        for t in types {
            if let r = rowRange(t), r.contains(fraction) { return t }
        }
        return nil
    }
}
