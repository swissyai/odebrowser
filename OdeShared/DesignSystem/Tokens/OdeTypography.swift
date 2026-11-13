import SwiftUI

/// Dynamic Type-aware roles for Ode's own surfaces.
///
/// Ode sets everything in the system font. Headings are the same face at a
/// heavier weight rather than a second, decorative face.
enum OdeTypography {
    /// The system UI font, by the name Core Text resolves to it.
    static let displayFontName = ".AppleSystemUIFont"
    static let sansFontName = ".AppleSystemUIFont"
    /// Display lines carry weight, not ornament.
    static let displayWeight: Font.Weight = .semibold

    static let controlTitle = Font.body.weight(.medium)
    static let metadata = Font.caption
    static let compactMetadata = Font.caption2
    static let badge = Font.caption2.monospaced().weight(.semibold)

    /// Display text that scales with Dynamic Type against `style`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(displayFontName, size: size, relativeTo: style).weight(displayWeight)
    }

    /// Display text at a fixed size, for layouts whose line breaks are composed
    /// by hand (the onboarding wizard).
    static func display(_ size: CGFloat) -> Font {
        .custom(displayFontName, size: size).weight(displayWeight)
    }

    /// Text at `size` that grows with the person's text size, against the
    /// system style of about that size.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(sansFontName, size: size, relativeTo: textStyle(near: size)).weight(weight)
    }

    /// The system text style closest to `size` on the Mac, which a custom
    /// size scales against.
    static func textStyle(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<10.5: .caption
        case ..<11.5: .subheadline
        case ..<12.5: .callout
        case ..<14.5: .body
        case ..<16.5: .title3
        case ..<21.5: .title2
        case ..<25.5: .title
        default: .largeTitle
        }
    }

    // MARK: - Named display roles

    /// Title of a single page or pane inside a Ode-authored flow.
    static let displayPageSize: CGFloat = 24
    /// Heading that opens a group of rows inside a pane.
    static let displaySectionSize: CGFloat = 17

    static var displayPage: Font { display(displayPageSize, relativeTo: .title2) }
    static var displaySection: Font { display(displaySectionSize, relativeTo: .title3) }
}
