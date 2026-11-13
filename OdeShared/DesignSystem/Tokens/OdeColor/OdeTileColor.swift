import SwiftUI

/// The fill of a coloured symbol tile, such as a Settings pane's: Ode blue,
/// the Command Bar's coral, one of the Space hues, or graphite. Each starts
/// at the Space swatch's lightness, a step deeper in dark mode, and moves
/// darker only as far as a white symbol needs to keep 3:1 on it, or 4.5:1
/// with Increase Contrast, so every tile reads the same at any hue.
struct OdeTileColor: Hashable, Sendable {
    // MARK: - Static Variables

    /// Ode blue, the blue of Ode's mark.
    static let blue = OdeTileColor(name: "blue", hue: 267.5)
    /// The Command Bar's coral.
    static let coral = OdeTileColor(name: "coral", hue: SpaceColorRoles.dangerHue)
    static let orange = OdeTileColor(name: "orange", preset: .orange)
    static let yellow = OdeTileColor(name: "yellow", preset: .yellow)
    static let green = OdeTileColor(name: "green", preset: .green)
    static let teal = OdeTileColor(name: "teal", preset: .teal)
    static let azure = OdeTileColor(name: "azure", preset: .azure)
    static let violet = OdeTileColor(name: "violet", preset: .violet)
    static let pink = OdeTileColor(name: "pink", preset: .pink)
    static let sand = OdeTileColor(name: "sand", hue: SpaceColorPreset.sand.inputs.hue, vividness: 0.45)
    static let graphite = OdeTileColor(name: "graphite", hue: 0, vividness: 0)

    static let all: [OdeTileColor] = [blue, coral, orange, yellow, green, teal, azure, violet, pink, sand, graphite]

    /// The white symbol's contrast floor on the tile, for a graphic.
    static let symbolContrast = 3.0
    static let increasedSymbolContrast = 4.5
    static let lightLightness = SpaceColorInputs.swatchLightness - 0.03
    static let darkLightness = SpaceColorInputs.swatchLightness - 0.08
    /// Graphite lifts its plain grey a little, so it doesn't read as disabled.
    static let graphiteChroma = 0.012
    static let maximumChroma = 0.16

    // MARK: - Variables

    /// The name tests and previews know the tile by.
    let name: String
    let hue: Double
    /// From 0 for grey to 1 for the hue at full chroma.
    let vividness: Double

    // MARK: - Initializers

    private init(name: String, hue: Double, vividness: Double = 1) {
        self.name = name
        self.hue = hue
        self.vividness = vividness
    }

    private init(name: String, preset: SpaceColorPreset) {
        self.init(name: name, hue: preset.inputs.hue)
    }

    // MARK: - Actions - Colour

    /// The tile's fill in `colorScheme`: the start lightness when a white
    /// symbol meets the floor there, else the lightest that does.
    func fill(colorScheme: ColorScheme, increasedContrast: Bool) -> OKLCHColor {
        let floor = increasedContrast ? Self.increasedSymbolContrast : Self.symbolContrast
        let white = OKLCHColor(lightness: 1, chroma: 0, hue: 0)
        var lightness = colorScheme == .dark ? Self.darkLightness : Self.lightLightness
        var color = make(lightness)
        while OKLCHColor.contrast(white, color) < floor, lightness > 0.2 {
            lightness -= 0.005
            color = make(lightness)
        }
        return color
    }

    private func make(_ lightness: Double) -> OKLCHColor {
        let chroma =
            vividness == 0
            ? Self.graphiteChroma
            : min(vividness * Self.maximumChroma, 0.9 * OKLCHColor.maximumChroma(lightness: lightness, hue: hue))
        return OKLCHColor(lightness: lightness, chroma: chroma, hue: vividness == 0 ? 265 : hue)
    }

    // MARK: - Actions - Identity

    static func == (lhs: OdeTileColor, rhs: OdeTileColor) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - ShapeStyle

extension OdeTileColor: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        fill(colorScheme: environment.colorScheme, increasedContrast: environment.colorSchemeContrast == .increased)
            .color.resolve(in: environment)
    }
}
