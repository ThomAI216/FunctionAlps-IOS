import SwiftUI
import UIKit

/// Loads brand media shipped as plain bundle files (WebP is decoded natively by
/// UIKit on iOS 14+, but asset catalogs do not accept it). Files live in
/// `Resources/Media/`; the Expo app is the source of these assets.
enum FAMedia {
    static func image(_ name: String, ext: String = "webp") -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

struct FABundledImage: View {
    let name: String
    var ext: String = "webp"
    var contentMode: ContentMode = .fit

    var body: some View {
        if let image = FAMedia.image(name, ext: ext) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            FABrandMark(size: 48)
        }
    }
}

/// The FunctionAlps mark — the peak and its reflection — as a one-colour glyph that takes any tint
/// (`Assets.xcassets/FAMark`, a template image made from the practice's white mark, CLINICAL
/// `public/brand/mark-white.webp`). Used where a small logo carries a colour: the check-in slider's thumb.
struct FAMarkGlyph: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        Image("FAMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The FA logo at the size the Expo login uses (200×96, contain).
struct FALogo: View {
    var height: CGFloat = 96
    var body: some View {
        FABundledImage(name: "fa-logo")
            .frame(height: height)
            .accessibilityLabel("FunctionAlps")
    }
}
