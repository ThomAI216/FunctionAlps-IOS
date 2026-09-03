import SwiftUI
import UIKit

/// Type ramp — DM Serif Display for display, DM Sans for everything else, the same two
/// families the web app loads (`lib/theme/tokens.ts` `fonts`). Point sizes are the ones that
/// recur on the web screens; every font is `relativeTo` a text style so Dynamic Type scales it.
enum FATypography {
    static let displayFace = "DMSerifDisplay-Regular"
    static let displayItalicFace = "DMSerifDisplay-Italic"
    static let sansFace = "DMSans-Regular"
    static let sansMediumFace = "DMSans-Medium"
    static let sansSemiboldFace = "DMSans-SemiBold"
    static let sansBoldFace = "DMSans-Bold"

    enum Weight { case regular, medium, semibold, bold }

    private static func name(for weight: Weight) -> String {
        switch weight {
        case .regular: sansFace
        case .medium: sansMediumFace
        case .semibold: sansSemiboldFace
        case .bold: sansBoldFace
        }
    }

    /// DM Serif Display at a web point size.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom(displayFace, size: size, relativeTo: style)
    }

    /// DM Sans at a web point size and weight.
    static func sans(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(name(for: weight), size: size, relativeTo: style)
    }

    // Semantic ramp (web sizes): page heading 26–30 display · card title 18 display ·
    // body 15 · callout 13.5 · caption 11.5 · label 10.5 semibold · metric 32 display.
    static var largeTitle: Font { display(28, relativeTo: .largeTitle) }
    static var title: Font { display(19, relativeTo: .title2) }
    static var headline: Font { sans(15, .semibold, relativeTo: .headline) }
    static var body: Font { sans(15, relativeTo: .body) }
    static var callout: Font { sans(13.5, relativeTo: .callout) }
    static var caption: Font { sans(11.5, relativeTo: .caption) }
    static var label: Font { sans(10.5, .semibold, relativeTo: .caption2) }
    static var metric: Font { display(32, relativeTo: .title) }
}

/// Spacing scale. `navBarClearance` mirrors `NAVBAR_CLEARANCE = 120` so the last card clears the floating bar.
enum FASpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let navBarClearance: CGFloat = 120
}

/// Mirrors `radii = { sm: 12, md: 16, lg: 22, xl: 24, pill: 200 }`; `glass` is the GlassCard's 25.
enum FACornerRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 24
    static let glass: CGFloat = 25
    static let pill: CGFloat = 200
}
