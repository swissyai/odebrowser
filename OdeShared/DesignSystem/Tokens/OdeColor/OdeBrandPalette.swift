import SwiftUI

/// Ode's fixed palette for first-party surfaces: near-black ink and warm paper,
/// Ode blue for primary actions and selection, and three Space presets (peach,
/// mint and sky at OKLCH 62% 0.18) for the few places that need a second
/// colour. The names are the code's; the colours are Ode's. Space colours stay
/// the person's own.
enum OdeBrandPalette {
    static let inkComponents = OdeColorComponents(red: 10, green: 10, blue: 10)
    static let inkSoftComponents = OdeColorComponents(red: 29, green: 29, blue: 29)
    static let paperComponents = OdeColorComponents(red: 246, green: 245, blue: 240)
    static let parchmentComponents = OdeColorComponents(red: 237, green: 237, blue: 237)
    /// Ode blue: primary actions, the current step and selection.
    static let butterComponents = OdeColorComponents(red: 48, green: 80, blue: 240)
    static let coralComponents = OdeColorComponents(red: 222, green: 78, blue: 75)
    static let sageComponents = OdeColorComponents(red: 35, green: 161, blue: 54)
    static let skyComponents = OdeColorComponents(red: 0, green: 149, blue: 220)

    static let ink = inkComponents.color
    static let inkSoft = inkSoftComponents.color
    static let paper = paperComponents.color
    static let parchment = parchmentComponents.color
    static let butter = butterComponents.color
    static let coral = coralComponents.color
    static let sage = sageComponents.color
    static let sky = skyComponents.color
    static let match = sage
    static let line = ink.opacity(OdeOpacity.brandHairline)
}
