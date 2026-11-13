import SwiftUI

/// The scheme-aware brand roles of Ode's own surfaces: one blue accent on a
/// warm paper ground in light, and the same roles on a near-black ground in
/// dark, as Ode's icon draws them.
///
/// Every pair clears WCAG AA for text (4.5:1) against both `canvas` and
/// `surface` in its scheme: the accent measures 5.45:1 and 5.95:1 in light
/// and 7.27:1 and 6.71:1 in dark, so the accent also serves as text.
enum OdeBrandTheme {
    // MARK: - Static Variables

    // Component pairs

    /// Ode blue, the blue of Ode's mark, and its lighter form for dark
    /// grounds.
    static let accentLightComponents = OdeColorComponents(red: 48, green: 80, blue: 240)
    static let accentDarkComponents = OdeColorComponents(red: 129, green: 161, blue: 246)

    /// The accent when it is text rather than a tint; the blue is legible as text.
    static let accentTextLightComponents = accentLightComponents
    static let accentTextDarkComponents = accentDarkComponents

    /// Warm paper in light, near-black in dark.
    static let canvasLightComponents = OdeColorComponents(red: 246, green: 245, blue: 240)
    static let canvasDarkComponents = OdeColorComponents(red: 21, green: 21, blue: 22)

    static let surfaceLightComponents = OdeColorComponents(red: 255, green: 255, blue: 255)
    static let surfaceDarkComponents = OdeColorComponents(red: 29, green: 29, blue: 29)

    static let textDisplayLightComponents = OdeColorComponents(red: 10, green: 10, blue: 10)
    static let textDisplayDarkComponents = OdeColorComponents(red: 250, green: 250, blue: 250)
    /// Display text held back for supporting copy. At 0.7 in light it keeps
    /// 7.3:1 or more on `canvas` and `surface`; at 0.6 in dark, 6.5:1 or more.
    static let textSecondaryLightOpacity = 0.7
    static let textSecondaryDarkOpacity = 0.6

    static let lineLightComponents = textDisplayLightComponents
    static let lineDarkComponents = textDisplayDarkComponents
    static let lineLightOpacity = 0.12
    static let lineDarkOpacity = 0.14

    /// A wash of display ink, faint enough to sit under text without taking
    /// from its contrast.
    static let quietFillLightOpacity = 0.05
    static let quietFillDarkOpacity = 0.08

    // Semantic roles

    /// Brand accent for interactive emphasis and tint.
    static let accent = dynamic(light: accentLightComponents, dark: accentDarkComponents)
    /// Brand accent for text-weight controls. See `accentTextLightComponents`.
    static let accentText = dynamic(
        light: accentTextLightComponents,
        dark: accentTextDarkComponents
    )
    /// The page the content sits on.
    static let canvas = dynamic(light: canvasLightComponents, dark: canvasDarkComponents)
    /// A raised card or panel on the canvas.
    static let surface = dynamic(light: surfaceLightComponents, dark: surfaceDarkComponents)
    /// Display and body text on `canvas` or `surface`.
    static let textDisplay = dynamic(
        light: textDisplayLightComponents,
        dark: textDisplayDarkComponents
    )
    /// Supporting text beside `textDisplay`: captions, counts, hints and notes.
    static let textSecondary = dynamic(
        light: textDisplayLightComponents,
        lightOpacity: textSecondaryLightOpacity,
        dark: textDisplayDarkComponents,
        darkOpacity: textSecondaryDarkOpacity
    )
    /// Hairline separators and control borders.
    static let line = dynamic(
        light: lineLightComponents,
        lightOpacity: lineLightOpacity,
        dark: lineDarkComponents,
        darkOpacity: lineDarkOpacity
    )
    /// The quiet ground of a panel or control that sits on `canvas` without
    /// rising to `surface`.
    static let quietFill = dynamic(
        light: textDisplayLightComponents,
        lightOpacity: quietFillLightOpacity,
        dark: textDisplayDarkComponents,
        darkOpacity: quietFillDarkOpacity
    )

    // MARK: - Actions - Resolving

    /// The role values as flat colors, for surfaces that already know which
    /// appearance they render in.
    static func accent(_ colorScheme: ColorScheme) -> Color {
        components(accentLightComponents, accentDarkComponents, colorScheme).color
    }

    static func accentText(_ colorScheme: ColorScheme) -> Color {
        components(accentTextLightComponents, accentTextDarkComponents, colorScheme).color
    }

    static func canvas(_ colorScheme: ColorScheme) -> Color {
        components(canvasLightComponents, canvasDarkComponents, colorScheme).color
    }

    static func surface(_ colorScheme: ColorScheme) -> Color {
        components(surfaceLightComponents, surfaceDarkComponents, colorScheme).color
    }

    static func textDisplay(_ colorScheme: ColorScheme) -> Color {
        components(textDisplayLightComponents, textDisplayDarkComponents, colorScheme).color
    }

    static func line(_ colorScheme: ColorScheme) -> Color {
        let base = components(lineLightComponents, lineDarkComponents, colorScheme)
        return base.color.opacity(colorScheme == .dark ? lineDarkOpacity : lineLightOpacity)
    }

    private static func components(
        _ light: OdeColorComponents,
        _ dark: OdeColorComponents,
        _ colorScheme: ColorScheme
    ) -> OdeColorComponents {
        colorScheme == .dark ? dark : light
    }

    // MARK: - Actions - Construction

    private static func dynamic(
        light: OdeColorComponents,
        lightOpacity: Double = 1,
        dark: OdeColorComponents,
        darkOpacity: Double = 1
    ) -> Color {
        OdePlatformDynamicColor.make(
            light: light,
            lightOpacity: lightOpacity,
            dark: dark,
            darkOpacity: darkOpacity
        )
    }
}
