import SwiftUI

/// The vivid ring a window wears around its page, where no text sits: the
/// Space's color as a strong mid-tone, deeper in dark mode but never near
/// black, turning across the window as the calm ground does, and muted while
/// the window isn't active, as macOS mutes an inactive window's sidebar.
/// Increase Contrast keeps the calm ground instead.
enum SpaceRingColor {
    // MARK: - Static Variables

    /// The ring's lightness in each appearance.
    static let lightLightness = 0.70
    static let darkLightness = 0.47
    /// How much of the hue's sRGB chroma edge the ring carries at its
    /// lightness, at full vividness.
    static let chromaShare = 0.72
    /// How much of its chroma the ring keeps while its window isn't active.
    static let inactiveChromaScale = 0.35
    /// How far the ring turns across the window: lighter and a little cooler
    /// toward one corner, deeper and a little warmer toward the other.
    static let lightnessTurn = 0.035
    static let hueTurn = 14.0

    // MARK: - Actions - Colors

    /// Whether the window shows the vivid ring, or the calm ground around
    /// the page as well, as Increase Contrast asks.
    static func showsRing(increasedContrast: Bool) -> Bool {
        !increasedContrast
    }

    /// The ring for `inputs` in `colorScheme`.
    static func color(_ inputs: SpaceColorInputs, colorScheme: ColorScheme, isActive: Bool) -> OKLCHColor {
        let lightness = colorScheme == .dark ? darkLightness : lightLightness
        return fitted(lightness: lightness, hue: inputs.hue, vividness: vividness(of: inputs), isActive: isActive)
    }

    /// The ring's two lights, toward the top leading and bottom trailing
    /// corners.
    static func lights(_ inputs: SpaceColorInputs, colorScheme: ColorScheme, isActive: Bool) -> [OKLCHColor] {
        let lightness = colorScheme == .dark ? darkLightness : lightLightness
        let vividness = vividness(of: inputs)
        return [
            fitted(
                lightness: lightness + lightnessTurn, hue: inputs.hue - hueTurn,
                vividness: vividness, isActive: isActive),
            fitted(
                lightness: lightness - lightnessTurn, hue: inputs.hue + hueTurn,
                vividness: vividness, isActive: isActive),
        ]
    }

    /// How colorful the Space is, from none for Graphite to its full hue.
    private static func vividness(of inputs: SpaceColorInputs) -> Double {
        inputs.isTinted ? min(max(inputs.vividness, 0), 1) : 0
    }

    private static func fitted(lightness: Double, hue: Double, vividness: Double, isActive: Bool) -> OKLCHColor {
        let chroma =
            chromaShare * OKLCHColor.maximumChroma(lightness: lightness, hue: hue) * vividness
            * (isActive ? 1 : inactiveChromaScale)
        return OKLCHColor(lightness: lightness, chroma: chroma, hue: hue).mappedToSRGB
    }
}
