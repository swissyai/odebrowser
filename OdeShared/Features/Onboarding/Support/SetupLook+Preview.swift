import SwiftUI

/// What a look shows of itself before any Space wears it: a color preset in
/// the look's own sidebar mode and icon style, as the core gives them to the
/// Spaces setup makes.
extension SetupLook {
    // MARK: - Static Variables

    /// The preset every look's preview starts from.
    private static let previewPreset = SpaceColorPreset.azure

    // MARK: - Variables

    /// The look on the preset every preview starts from.
    var previewBranding: SpaceBranding { applying(to: Self.previewPreset.branding) }

    /// The look's name as setup shows it. The core names the first look for
    /// the heraldry it once drew; Ode draws it as a solid tint.
    var shownTitle: LocalizedStringResource {
        switch kind {
        case .heraldic: "Tinted"
        case .modern: "Gradient"
        }
    }

    /// The symbol a previewed Space wears as its icon.
    var previewSymbol: String { "house.fill" }

    // MARK: - Actions - Looks

    /// `branding` in this look: the sidebar mode and gradient angle the core
    /// gives the look and the symbol icon style, keeping its colors.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var look = branding
        look.themeMode = themeMode
        look.gradientAngle = gradientAngle ?? branding.gradientAngle
        // Ode draws every Space's icon as a symbol, whatever the look.
        look.iconStyle = .simpleSymbol
        return look.normalized()
    }
}
