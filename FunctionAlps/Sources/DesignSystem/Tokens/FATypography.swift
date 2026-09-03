import SwiftUI
import UIKit

/// Type ramp. The Expo app uses DM Serif Display (display) + DM Sans (body), both
/// OFL-licensed Google fonts. Until the TTFs are added to `Resources/Fonts` and
/// listed under `UIAppFonts` in project.yml, the closest system faces are used.
/// All sizes are relative so Dynamic Type keeps working (PRD §50).
enum FATypography {
    static let displayFamily = "DMSerifDisplay-Regular"
    static let bodyFamily = "DMSans-Regular"
    static let bodyMediumFamily = "DMSans-Medium"
    static let bodySemiboldFamily = "DMSans-SemiBold"
    static let bodyBoldFamily = "DMSans-Bold"

    private static func custom(_ name: String, _ style: Font.TextStyle, fallbackDesign: Font.Design, weight: Font.Weight) -> Font {
        if UIFont.familyNames.contains(where: { $0.hasPrefix("DM") }) {
            return .custom(name, size: UIFont.preferredFont(forTextStyle: style.uiKit).pointSize, relativeTo: style)
        }
        return .system(style, design: fallbackDesign, weight: weight)
    }

    static var largeTitle: Font { custom(displayFamily, .largeTitle, fallbackDesign: .serif, weight: .regular) }
    static var title: Font { custom(displayFamily, .title2, fallbackDesign: .serif, weight: .regular) }
    static var headline: Font { custom(bodySemiboldFamily, .headline, fallbackDesign: .default, weight: .semibold) }
    static var body: Font { custom(bodyFamily, .body, fallbackDesign: .default, weight: .regular) }
    static var callout: Font { custom(bodyFamily, .callout, fallbackDesign: .default, weight: .regular) }
    static var caption: Font { custom(bodyFamily, .caption, fallbackDesign: .default, weight: .regular) }
    static var label: Font { custom(bodySemiboldFamily, .caption, fallbackDesign: .default, weight: .semibold) }
    static var metric: Font { custom(displayFamily, .title, fallbackDesign: .serif, weight: .regular) }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

/// Spacing scale. The Expo app has no custom scale (inline RN numbers); these are
/// the values that recur there. `navBarClearance` mirrors `NAVBAR_CLEARANCE = 120`.
enum FASpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let navBarClearance: CGFloat = 120
}

/// Mirrors `radii = { sm: 12, md: 16, lg: 22, xl: 24, pill: 200 }`.
enum FACornerRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 24
    static let pill: CGFloat = 200
}
