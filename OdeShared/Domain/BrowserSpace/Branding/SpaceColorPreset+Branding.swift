import Foundation

extension SpaceColorPreset {
    /// A look wearing this preset alone: its swatch as the one color, the
    /// symbol icon style, and nothing else changed from the neutral look.
    var branding: SpaceBranding {
        var look = SpaceBranding.neutral
        look.colors = ColorPalette(colors: [swatch])
        look.iconStyle = .simpleSymbol
        return look
    }

    /// The preset nearest `inputs`: Graphite for a Space with no color, else
    /// the chromatic preset whose hue is closest.
    static func nearest(to inputs: SpaceColorInputs) -> SpaceColorPreset {
        guard inputs.isTinted, inputs.vividness > 0 else { return .graphite }
        let chromatic = all.filter { $0.inputs.vividness == 1 }
        return chromatic.min { distance($0.inputs.hue, inputs.hue) < distance($1.inputs.hue, inputs.hue) } ?? .azure
    }

    /// How far in OKLab a look's color may sit from a preset's swatch and
    /// still read as that preset: about two and a half just-noticeable
    /// differences, under half the distance between neighboring presets.
    static let wornDistance = 0.05

    /// The preset `branding` wears: the one whose swatch is nearest the
    /// look's most colorful color, when within `wornDistance`; nil for a
    /// color no preset is close to.
    static func worn(by branding: SpaceBranding) -> SpaceColorPreset? {
        let seed = OKLCHColor(branding.seedColor).lab
        func distance(to preset: SpaceColorPreset) -> Double {
            let difference = OKLCHColor(preset.swatch).lab - seed
            return (difference * difference).sum().squareRoot()
        }
        guard let nearest = all.min(by: { distance(to: $0) < distance(to: $1) }),
            distance(to: nearest) <= wornDistance
        else { return nil }
        return nearest
    }

    private static func distance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
