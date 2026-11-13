import SwiftUI
import Synchronization

/// What a Space's colors are worked out from: the hue of its color, how vivid
/// its accents are, and how strongly its grounds are tinted, each from 0 to 1.
struct SpaceColorInputs: Equatable, Sendable {
    // MARK: - Static Variables

    /// No tint and no accent color: a neutral Space.
    static let graphite = SpaceColorInputs(hue: 0, vividness: 0, intensity: 0)
    /// The tint a Space gets until it stores its own.
    static let defaultIntensity = 0.5

    // MARK: - Variables

    var hue: Double
    var vividness: Double
    var intensity: Double

    /// Whether the Space carries any color at all; Graphite carries none, so
    /// even its text stays neutral.
    var isTinted: Bool {
        vividness > 0 || intensity > 0
    }
}

extension SpaceColorInputs {
    // MARK: - Static Variables

    /// The lightness a swatch and the picker's dots are drawn at.
    static let swatchLightness = 0.65
    /// Below this chroma a stored color reads as gray, and its Space as
    /// Graphite.
    static let grayChroma = 0.02

    // MARK: - Initializers

    /// The inputs a stored color implies: its hue, and its chroma measured
    /// against the chroma a swatch of that hue carries. A gray color is
    /// Graphite.
    init(color: BrandColor, intensity: Double = defaultIntensity) {
        let oklch = OKLCHColor(color)
        guard oklch.chroma >= Self.grayChroma else {
            self = .graphite
            return
        }
        self.init(
            hue: oklch.hue,
            vividness: min(1, oklch.chroma / Self.swatchChroma(hue: oklch.hue)),
            intensity: intensity
        )
    }

    // MARK: - Actions - Swatch

    /// The chroma a fully vivid swatch of `hue` carries: as much as sRGB
    /// allows at the swatch lightness, up to 0.19.
    static func swatchChroma(hue: Double) -> Double {
        min(0.19, 0.9 * OKLCHColor.maximumChroma(lightness: swatchLightness, hue: hue))
    }
}

/// The colors a Space draws its window with, one per role. Each role starts
/// at a fixed OKLCH lightness and moves along lightness, at its own hue and
/// chroma, only as far as it must to meet its contrast floor against every
/// ground it is drawn on, so its contrast holds for every hue. Increase
/// Contrast raises the floors rather than shifting lightness by a constant.
/// Chroma comes from a budget that tints every hue equally up to the default
/// intensity, then lets each hue use up to 85% of its own sRGB gamut edge.
struct SpaceColorRoles: Equatable, Sendable {
    // MARK: - Types

    /// The lightness each role starts from in one appearance.
    private struct Ladder {
        var window: Double
        var sidebar: Double
        var hover: Double
        var selected: Double
        var separator: Double
        var text: Double
        var secondaryText: Double
        var accentText: Double
        var accentSolid: Double
        var labelOnSolid: Double
        var scrim: Double

        static let light = Ladder(
            window: 0.955, sidebar: 0.93, hover: 0.895, selected: 0.985, separator: 0.835,
            text: 0.25, secondaryText: 0.47, accentText: 0.47, accentSolid: 0.54, labelOnSolid: 1, scrim: 0.15)
        static let dark = Ladder(
            window: 0.175, sidebar: 0.205, hover: 0.25, selected: 0.295, separator: 0.33,
            text: 0.94, secondaryText: 0.80, accentText: 0.83, accentSolid: 0.77, labelOnSolid: 0.15, scrim: 0.08)

        /// Increase Contrast widens the gap between text and ground; the
        /// grounds keep their lightness and chroma.
        func increasingContrast(dark: Bool) -> Ladder {
            var ladder = self
            ladder.text = dark ? 0.97 : 0.18
            ladder.secondaryText = dark ? 0.84 : 0.38
            ladder.accentText = dark ? 0.86 : 0.40
            ladder.accentSolid = dark ? 0.80 : 0.48
            ladder.separator = dark ? 0.45 : 0.75
            ladder.hover = dark ? 0.27 : 0.88
            return ladder
        }
    }

    /// The WCAG contrast each role keeps against the grounds it is drawn on.
    struct Floors: Equatable, Sendable {
        /// Text against the sidebar, hover, selected and window grounds.
        var text: Double
        /// Secondary text against the sidebar, hover and selected grounds.
        var secondaryText: Double
        /// Accent text, the Space's name, against the sidebar and hover.
        var accentText: Double
        /// The solid accent against the sidebar, hover and selected grounds.
        var accentSolid: Double
        /// The label on the solid accent.
        var labelOnSolid: Double
        /// The selected row's ring against the sidebar, where it is the
        /// selection's second cue; nil where the ladder's hairline stays.
        var selectionRing: Double?
        /// Error text, and the symbol of something waiting on the person.
        var dangerText: Double
        var cautionSymbol: Double
        /// White on the Command Bar's selected row, and its secondary label.
        var commandBarLabel: Double
        var commandBarSecondaryLabel: Double

        static let standard = Floors(
            text: 7, secondaryText: 4.8, accentText: 5, accentSolid: 3.4, labelOnSolid: 5, selectionRing: nil,
            dangerText: 5, cautionSymbol: 3.4, commandBarLabel: 6, commandBarSecondaryLabel: 4.6)
        static let increased = Floors(
            text: 11, secondaryText: 7, accentText: 7, accentSolid: 4.5, labelOnSolid: 7, selectionRing: 3.2,
            dangerText: 7, cautionSymbol: 4.5, commandBarLabel: 7, commandBarSecondaryLabel: 7)
    }

    private struct CacheKey: Hashable {
        let hue: Int
        let vividness: Int
        let intensity: Int
        let dark: Bool
        let increasedContrast: Bool
        let isActive: Bool
    }

    // MARK: - Static Variables

    /// How far below a hue's gamut edge a ground's chroma stays, so grain and
    /// blending never clip.
    static let groundClearance = 0.85
    /// A floating sidebar keeps the window's hue and chroma, one small
    /// perceptual step deeper in either appearance.
    private static let floatingSidebarLightnessStep = 0.025
    /// The scrim's opacity over the page.
    static let scrimOpacity = 0.32
    /// The hue error text and a waiting symbol take, whatever the Space's.
    static let dangerHue = 27.0
    static let cautionHue = 65.0
    /// The lightness the Command Bar's selected row starts from.
    static let commandBarSelectionLightness = 0.48
    static let commandBarSelectionMaximumChroma = 0.16

    private static let uniformBudgetCache = Mutex<[Int: Double]>([:])
    private static let rolesCache = Mutex<[CacheKey: SpaceColorRoles]>([:])

    // MARK: - Variables

    /// The appearance these roles are for; a view drawn in the other one
    /// falls back to the platform's colors.
    let colorScheme: ColorScheme
    let window: OKLCHColor
    let sidebar: OKLCHColor
    let hover: OKLCHColor
    let selected: OKLCHColor
    let separator: OKLCHColor
    let text: OKLCHColor
    let secondaryText: OKLCHColor
    let accentText: OKLCHColor
    let accentSolid: OKLCHColor
    let labelOnSolid: OKLCHColor
    let scrim: OKLCHColor
    /// A failed download's status and other error text on the Space's
    /// grounds, in a red of its own.
    let dangerText: OKLCHColor
    /// The symbol of something that waits on the person, in an orange of its
    /// own.
    let cautionSymbol: OKLCHColor
    /// The Command Bar's selected row: the Space's hue, deep enough for
    /// white text and its secondary label.
    let commandBarSelection: OKLCHColor
    /// How opaque white draws the selected row's secondary text.
    let commandBarSecondaryLabelOpacity: Double
    /// The contrast floors these roles were solved for.
    let floors: Floors

    var floatingSidebar: OKLCHColor {
        let ground = OKLCHColor(
            lightness: max(0, window.lightness - Self.floatingSidebarLightnessStep),
            chroma: window.chroma, hue: window.hue
        ).mappedToSRGB
        guard OKLCHColor.contrast(text, ground) >= floors.text,
            OKLCHColor.contrast(secondaryText, ground) >= floors.secondaryText,
            OKLCHColor.contrast(accentText, ground) >= floors.accentText,
            OKLCHColor.contrast(dangerText, ground) >= floors.dangerText,
            OKLCHColor.contrast(cautionSymbol, ground) >= floors.cautionSymbol
        else { return window }
        return ground
    }

    // MARK: - Initializers

    /// The roles for `inputs` in `colorScheme`. An inactive window keeps
    /// every lightness and halves the chroma of its grounds and solid.
    init(
        _ inputs: SpaceColorInputs,
        colorScheme: ColorScheme,
        increasedContrast: Bool = false,
        isActive: Bool = true
    ) {
        let key = CacheKey(
            hue: Int((OKLCHColor(lightness: 0.5, chroma: 0, hue: inputs.hue).hue * 100).rounded()),
            vividness: Int((min(max(inputs.vividness, 0), 1) * 10_000).rounded()),
            intensity: Int((min(max(inputs.intensity, 0), 1) * 10_000).rounded()),
            dark: colorScheme == .dark, increasedContrast: increasedContrast, isActive: isActive)
        if let known = Self.rolesCache.withLock({ $0[key] }) {
            self = known
            return
        }
        self.init(solving: inputs, colorScheme: colorScheme, increasedContrast: increasedContrast, isActive: isActive)
        let solved = self
        Self.rolesCache.withLock { cache in
            if cache.count >= 512 { cache.removeAll(keepingCapacity: true) }
            cache[key] = solved
        }
    }

    private init(solving inputs: SpaceColorInputs, colorScheme: ColorScheme, increasedContrast: Bool, isActive: Bool) {
        self.colorScheme = colorScheme
        let dark = colorScheme == .dark
        let ladder =
            increasedContrast
            ? (dark ? Ladder.dark : Ladder.light).increasingContrast(dark: dark)
            : (dark ? Ladder.dark : Ladder.light)
        let floors = increasedContrast ? Floors.increased : Floors.standard
        self.floors = floors
        let hue = inputs.hue
        let vividness = min(max(inputs.vividness, 0), 1)
        let tint = inputs.isTinted ? 1.0 : 0
        let quiet = isActive ? 1.0 : 0.5
        let groundChroma = Self.groundChroma(lightness: ladder.sidebar, hue: hue, intensity: inputs.intensity)
        // Foregrounds move away from the grounds: darker in light, lighter in dark.
        let away = dark ? 1.0 : -1.0

        func role(_ chroma: Double, within share: Double, scaledBy scale: Double = 1, hue: Double = hue)
            -> (Double) -> OKLCHColor
        {
            { lightness in
                let limit = share * OKLCHColor.maximumChroma(lightness: lightness, hue: hue)
                return OKLCHColor(lightness: lightness, chroma: min(chroma, limit) * scale, hue: hue)
            }
        }
        func ground(_ lightness: Double, _ chroma: Double) -> OKLCHColor {
            role(chroma, within: Self.groundClearance, scaledBy: quiet)(lightness)
        }
        func reaching(_ minimum: Double, against grounds: [OKLCHColor]) -> (OKLCHColor) -> Bool {
            let luminances = grounds.map(\.relativeLuminance)
            return { color in
                let own = color.relativeLuminance
                return luminances.allSatisfy { OKLCHColor.contrast(luminance: own, $0) >= minimum }
            }
        }

        window = ground(ladder.window, (dark ? 0.8 : 0.6) * groundChroma)
        sidebar = ground(ladder.sidebar, groundChroma)
        hover = ground(ladder.hover, 1.15 * groundChroma)
        selected = ground(ladder.selected, (dark ? 1.0 : 0.35) * groundChroma)
        scrim = OKLCHColor(lightness: ladder.scrim, chroma: min(0.02, groundChroma), hue: hue)

        let textGrounds = [sidebar, hover, selected, window]
        let rowGrounds = [sidebar, hover, selected]
        text = Self.solve(
            from: ladder.text, away: away, role(tint * (dark ? 0.015 : 0.035), within: 0.5),
            meets: reaching(floors.text, against: textGrounds))
        secondaryText = Self.solve(
            from: ladder.secondaryText, away: away, role(tint * (dark ? 0.03 : 0.04), within: 0.5),
            meets: reaching(floors.secondaryText, against: rowGrounds))
        accentText = Self.solve(
            from: ladder.accentText, away: away, role(vividness * (dark ? 0.14 : 0.17), within: 0.9),
            meets: reaching(floors.accentText, against: [sidebar, hover]))
        let label =
            dark
            ? role(tint * 0.02, within: 0.5)(ladder.labelOnSolid) : OKLCHColor(lightness: 1, chroma: 0, hue: hue)
        labelOnSolid = label
        let solidAgainstGrounds = reaching(floors.accentSolid, against: rowGrounds)
        let labelOnIt = reaching(floors.labelOnSolid, against: [label])
        accentSolid = Self.solve(
            from: ladder.accentSolid, away: away, role(vividness * (dark ? 0.16 : 0.20), within: 0.9, scaledBy: quiet),
            meets: { solidAgainstGrounds($0) && labelOnIt($0) })
        if let ring = floors.selectionRing {
            separator = Self.solve(
                from: ladder.separator, away: away, role(groundChroma, within: Self.groundClearance, scaledBy: quiet),
                meets: reaching(ring, against: [sidebar]))
        } else {
            separator = ground(ladder.separator, groundChroma)
        }
        dangerText = Self.solve(
            from: dark ? 0.80 : 0.50, away: away, role(dark ? 0.13 : 0.19, within: 0.9, hue: Self.dangerHue),
            meets: reaching(floors.dangerText, against: rowGrounds))
        cautionSymbol = Self.solve(
            from: dark ? 0.82 : 0.62, away: away, role(dark ? 0.14 : 0.16, within: 0.9, hue: Self.cautionHue),
            meets: reaching(floors.cautionSymbol, against: rowGrounds))

        let secondaryOpacity = increasedContrast ? 1.0 : 0.85
        commandBarSecondaryLabelOpacity = secondaryOpacity
        let solid = accentSolid
        commandBarSelection = Self.solve(
            from: Self.commandBarSelectionLightness, away: -1,
            { lightness in
                let chroma = min(
                    solid.chroma, Self.commandBarSelectionMaximumChroma,
                    0.9 * OKLCHColor.maximumChroma(lightness: lightness, hue: solid.hue))
                return OKLCHColor(lightness: lightness, chroma: chroma, hue: solid.hue)
            },
            meets: { fill in
                let ground = fill.srgbComponents
                let white = SIMD3<Double>(repeating: 1)
                let secondary = white * secondaryOpacity + ground * (1 - secondaryOpacity)
                let keycap = white * 0.1 + ground * 0.9
                return OKLCHColor.contrast(srgb: white, ground) >= floors.commandBarLabel
                    && OKLCHColor.contrast(srgb: secondary, ground) >= floors.commandBarSecondaryLabel
                    && OKLCHColor.contrast(srgb: white, keycap) >= 4.5
            })
    }

    // MARK: - Actions - Solving

    /// The color `make` gives at the lightness nearest `start`, moving
    /// `away` (+1 lighter, -1 darker), that `meets` its floor; the far end
    /// of the range when none does.
    private static func solve(
        from start: Double, away direction: Double, _ make: (Double) -> OKLCHColor,
        meets: (OKLCHColor) -> Bool
    ) -> OKLCHColor {
        let first = make(start)
        if meets(first) { return first }
        let end = direction < 0 ? 0.02 : 0.995
        guard meets(make(end)) else { return make(end) }
        var failing = start
        var passing = end
        for _ in 0..<24 {
            let middle = (failing + passing) / 2
            if meets(make(middle)) { passing = middle } else { failing = middle }
        }
        return make(passing)
    }

    // MARK: - Actions - Chroma

    /// The sidebar's chroma: up to the default intensity every hue gets the
    /// same uniform budget, so all hues look equally tinted; above it, each
    /// hue grows toward 85% of its own gamut edge.
    static func groundChroma(lightness: Double, hue: Double, intensity: Double) -> Double {
        let intensity = min(max(intensity, 0), 1)
        let uniform = uniformBudget(lightness: lightness)
        let edge = groundClearance * OKLCHColor.maximumChroma(lightness: lightness, hue: hue)
        let chroma =
            intensity <= 0.5
            ? uniform * intensity / 0.5
            : uniform + (intensity - 0.5) / 0.5 * max(0, edge - uniform)
        return min(chroma, edge)
    }

    /// 85% of the smallest sRGB maximum chroma over every hue at this
    /// lightness: the most any hue can carry and still match all the others.
    static func uniformBudget(lightness: Double) -> Double {
        let key = Int((lightness * 10_000).rounded())
        if let known = uniformBudgetCache.withLock({ $0[key] }) { return known }
        var smallest = Double.greatestFiniteMagnitude
        for hue in stride(from: 0.0, to: 360.0, by: 1.0) {
            smallest = min(smallest, OKLCHColor.maximumChroma(lightness: lightness, hue: hue))
        }
        let budget = groundClearance * smallest
        uniformBudgetCache.withLock { $0[key] = budget }
        return budget
    }
}
