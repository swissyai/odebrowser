import Foundation

/// The Space colors Ode offers by name. Each is a hue at the vividness and
/// intensity its swatch implies; eight hues spread around the wheel, kept
/// clear of the app accent's hue so a Space's color is never read as a
/// control's, plus a warm neutral and a neutral with no tint at all.
struct SpaceColorPreset: Hashable, Sendable {
    // MARK: - Static Variables

    static let red = SpaceColorPreset(name: "red", title: "Red", hue: 25)
    static let orange = SpaceColorPreset(name: "orange", title: "Orange", hue: 60)
    static let yellow = SpaceColorPreset(name: "yellow", title: "Yellow", hue: 95)
    static let green = SpaceColorPreset(name: "green", title: "Green", hue: 145)
    static let teal = SpaceColorPreset(name: "teal", title: "Teal", hue: 190)
    static let azure = SpaceColorPreset(name: "azure", title: "Azure", hue: 235)
    static let violet = SpaceColorPreset(name: "violet", title: "Violet", hue: 300)
    static let pink = SpaceColorPreset(name: "pink", title: "Pink", hue: 345)
    static let sand = SpaceColorPreset(name: "sand", title: "Sand", hue: 80, vividness: 0.35, intensity: 0.35)
    static let graphite = SpaceColorPreset(name: "graphite", title: "Graphite", hue: 0, vividness: 0, intensity: 0)

    static let all: [SpaceColorPreset] = [
        .red, .orange, .yellow, .green, .teal, .azure, .violet, .pink, .sand, .graphite,
    ]

    // MARK: - Variables

    /// The name automation and stored choices use.
    let name: String
    let title: LocalizedStringResource
    let inputs: SpaceColorInputs

    /// The color a Space wearing this preset stores, and the picker's dot:
    /// the hue at the swatch lightness, as vivid as the preset is.
    var swatch: BrandColor {
        OKLCHColor(
            lightness: SpaceColorInputs.swatchLightness,
            chroma: inputs.vividness * SpaceColorInputs.swatchChroma(hue: inputs.hue),
            hue: inputs.hue
        ).brandColor
    }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, hue: Double, vividness: Double = 1,
        intensity: Double = SpaceColorInputs.defaultIntensity
    ) {
        self.name = name
        self.title = title
        inputs = SpaceColorInputs(hue: hue, vividness: vividness, intensity: intensity)
    }

    // MARK: - Actions - Identity

    static func == (lhs: SpaceColorPreset, rhs: SpaceColorPreset) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
