import SwiftUI

/// A Space's look as a window draws it: grounds whose lightness follows the
/// windows' appearance, tinted by the Space's color, under text that follows
/// the appearance too.
extension SpaceBranding {
    // MARK: - Variables

    /// What the Space's role colors are worked out from: the hue and
    /// vividness of its most colorful color, which for a one-color Space is
    /// that color. Older multi-color looks list their darkest, grayest color
    /// first, so the first color alone would read as gray. Every Space has
    /// the default tint until it stores its own.
    var colorInputs: SpaceColorInputs {
        SpaceColorInputs(color: seedColor)
    }

    /// The look's most colorful color, which its roles and its preset are
    /// worked out from.
    var seedColor: BrandColor {
        colors.max { OKLCHColor($0).chroma < OKLCHColor($1).chroma } ?? backgroundColor
    }

    /// The colors the Space's palette lights its ground with when it is a
    /// gradient: up to three, at most one per distinct color.
    var groundLightColors: [BrandColor] {
        guard themeMode == .gradient else { return [] }
        var lights: [BrandColor] = []
        for color in colors where !lights.contains(where: { $0.matches(color) }) {
            lights.append(color)
        }
        return lights.count > 1 ? Array(lights.prefix(3)) : []
    }

    /// The tone the Space's text takes in the windows' current appearance.
    /// A Space's grounds are light in a light appearance and dark in a dark
    /// one, whatever its color, so its text is dark or light with them.
    @MainActor
    var foregroundTone: BrowserSpaceForegroundTone {
        BrowserDeviceAppearanceStore.shared.shownColorScheme == .dark ? .light : .dark
    }

    // MARK: - Actions - Text

    /// The tone the Space's text reads in over a window in `appearance`. Its
    /// grounds follow the appearance, so its text does too.
    func foregroundTone(over appearance: ColorScheme) -> BrowserSpaceForegroundTone {
        appearance == .dark ? .light : .dark
    }

    /// The scheme the Space's sidebar draws in over a window in `appearance`.
    func colorScheme(over appearance: ColorScheme) -> ColorScheme {
        foregroundTone(over: appearance).colorScheme
    }
}
