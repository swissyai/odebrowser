import SwiftUI

/// Semantic colors for Ode-authored chrome. Space identity colors remain data-driven.
enum OdeColor {
    static let selection = Color.primary.opacity(OdeOpacity.selection)
    static let chromeSurface = Color.primary.opacity(OdeOpacity.chromeSurface)
    static let hover = Color.primary.opacity(OdeOpacity.hover)
    static let subtleBorder = Color.primary.opacity(OdeOpacity.border)
    static let selectedBorder = Color.primary.opacity(OdeOpacity.selectedBorder)
    static let dropIndicator = OdeBrandPalette.paper.opacity(OdeOpacity.dropIndicator)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// The platform's own window background, under a Space's colors.
    #if os(macOS)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
    #else
        static let windowBackground = Color(uiColor: .systemBackground)
    #endif

    // MARK: - Status

    // The house tinctures ember, gold and sage, darkened in light and lifted
    // in dark until each reads as text at 4.5:1 or more on the window, form,
    // grouped-list and paper surfaces Ode draws in either appearance. Dark
    // danger also keeps 3:1 under a white glyph, as a remove button draws it.

    /// Something failed, was refused or is unsafe.
    static let danger = status(
        light: OdeColorComponents(red: 178, green: 50, blue: 37),
        dark: OdeColorComponents(red: 238, green: 106, blue: 92))
    /// Something needs the person: a decision, a fix, or a caution to read.
    static let warning = status(
        light: OdeColorComponents(red: 138, green: 90, blue: 8),
        dark: OdeColorComponents(red: 236, green: 190, blue: 92))
    /// Something is settled and fine: allowed, secure, ready.
    static let success = status(
        light: OdeColorComponents(red: 47, green: 112, blue: 66),
        dark: OdeColorComponents(red: 134, green: 196, blue: 142))
    /// The wash under a row or tag that is in danger.
    static let dangerFill = danger.opacity(OdeOpacity.statusFill)
    /// The wash under a row or tag that needs the person.
    static let warningFill = warning.opacity(OdeOpacity.statusFill)

    private static func status(light: OdeColorComponents, dark: OdeColorComponents) -> Color {
        OdePlatformDynamicColor.make(light: light, lightOpacity: 1, dark: dark, darkOpacity: 1)
    }
}

/// Secondary text on Ode's own panels, the Command Bar, tab previews and the
/// Boost popovers: a neutral gray at a fixed OKLCH lightness that keeps 4.5:1
/// on the panel in either appearance, and 7:1 with Increase Contrast, where
/// the system's secondary label falls to about 3.2:1 in dark.
struct OdePanelDetailStyle: ShapeStyle {
    static let lightLightness = 0.52
    static let darkLightness = 0.80
    static let increasedLightLightness = 0.40
    static let increasedDarkLightness = 0.88

    static func color(colorScheme: ColorScheme, increasedContrast: Bool) -> OKLCHColor {
        let dark = colorScheme == .dark
        let lightness =
            increasedContrast
            ? (dark ? increasedDarkLightness : increasedLightLightness) : (dark ? darkLightness : lightLightness)
        return OKLCHColor(lightness: lightness, chroma: 0, hue: 0)
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        Self.color(
            colorScheme: environment.colorScheme, increasedContrast: environment.colorSchemeContrast == .increased
        ).color.resolve(in: environment)
    }
}

extension ShapeStyle where Self == OdePanelDetailStyle {
    /// Secondary text on Ode's own panels.
    static var panelDetail: OdePanelDetailStyle { OdePanelDetailStyle() }
}
