import SwiftUI

/// Forwards to `OdeTypography` so the wizard and the rest of the app share
/// one type scale. Kept as a name because the wizard's call sites are
/// hand-composed.
enum BrowserOnboardingTypography {
    static func display(_ size: CGFloat) -> Font {
        OdeTypography.display(size)
    }

    static func sans(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        OdeTypography.sans(size, weight: weight)
    }
}
