import SwiftUI

/// One of a gradient Space's colors as a light over its ground: the color's
/// hue at the ground's lightness, with the chroma a ground of that hue would
/// carry. Every light keeps the ground's lightness, so text over the ground
/// keeps its contrast wherever a light falls.
enum SpaceGroundLight {
    static func color(_ color: BrandColor, over ground: OKLCHColor, intensity: Double, isActive: Bool) -> OKLCHColor {
        let inputs = SpaceColorInputs(color: color, intensity: intensity)
        let chroma =
            inputs.isTinted
            ? SpaceColorRoles.groundChroma(lightness: ground.lightness, hue: inputs.hue, intensity: intensity) : 0
        return OKLCHColor(lightness: ground.lightness, chroma: chroma * (isActive ? 1 : 0.5), hue: inputs.hue)
            .mappedToSRGB
    }
}

extension SpaceGroundLight {
    /// How far a one-color Space's hue turns each way across its ground.
    static let derivedHueTurn = 14.0
    /// How much lighter a light ground's top leading corner gets, and how
    /// much darker a dark ground's bottom trailing corner: away from the
    /// text in both, so text keeps at least its contrast on the ground.
    static let derivedLightnessShift = 0.022

    /// A one-color Space's ground as a gentle gradient: its hue turned a
    /// little toward the top leading corner and a little the other way toward
    /// the bottom trailing one, with the lightness moved only away from the
    /// text. Graphite, which has no hue, gets the lightness alone.
    static func derived(over ground: OKLCHColor, colorScheme: ColorScheme) -> [OKLCHColor] {
        let dark = colorScheme == .dark
        let lead = OKLCHColor(
            lightness: dark ? ground.lightness : min(ground.lightness + derivedLightnessShift, 0.99),
            chroma: ground.chroma, hue: ground.hue - derivedHueTurn)
        let trail = OKLCHColor(
            lightness: dark ? max(ground.lightness - derivedLightnessShift, 0.05) : ground.lightness,
            chroma: ground.chroma, hue: ground.hue + derivedHueTurn)
        let groundLuminance = ground.relativeLuminance
        return [lead, trail].map { light in
            var lightness = light.lightness
            var color = fitted(lightness: lightness, chroma: light.chroma, hue: light.hue)
            // A turned hue can carry a little less luminance at the same
            // lightness; step away from the text until it carries at least
            // the ground's distance from it.
            for _ in 0..<40 {
                let farEnough =
                    dark ? color.relativeLuminance <= groundLuminance : color.relativeLuminance >= groundLuminance
                if farEnough { break }
                lightness += dark ? -0.002 : 0.002
                color = fitted(lightness: lightness, chroma: light.chroma, hue: light.hue)
            }
            return color
        }
    }

    /// The color at `lightness` and `hue`, with no more chroma than a ground
    /// of that hue can carry there.
    private static func fitted(lightness: Double, chroma: Double, hue: Double) -> OKLCHColor {
        let lightness = min(max(lightness, 0.02), 0.995)
        let ceiling = SpaceColorRoles.groundClearance * OKLCHColor.maximumChroma(lightness: lightness, hue: hue)
        return OKLCHColor(lightness: lightness, chroma: min(chroma, ceiling), hue: hue).mappedToSRGB
    }
}

/// A Space's ground with up to three lights over it, mixed in OKLab. Two
/// lights sit in opposite corners and three at the top corners and the
/// bottom middle; each fades out smoothly, so opposite colors meet at the
/// ground's own color instead of turning to mud between them. The mix is
/// worked out at the vertices of a mesh and drawn between them in device
/// space, rather than left to an unnamed perceptual interpolation.
struct BrowserSpaceGroundField: View {
    // MARK: - Static Variables

    nonisolated static let meshColumns = 5
    nonisolated static let meshRows = 5
    /// How far a light reaches across the unit square, and how strong it is
    /// at its anchor.
    nonisolated static let lightReach = 1.0
    nonisolated static let lightPeak = 0.9

    // MARK: - Variables

    let ground: OKLCHColor
    let lights: [OKLCHColor]

    var body: some View {
        if lights.isEmpty {
            Rectangle().fill(ground.color)
        } else if lights.count == 2 {
            // Two lights sit in opposite corners, so the field runs along the
            // diagonal; a linear gradient through its colors draws it for far
            // less than a mesh, which every Space's backdrop redraws as the
            // window changes.
            LinearGradient(
                stops: Self.diagonalStops(ground: ground, lights: lights).map {
                    Gradient.Stop(color: $0.color.color, location: $0.location)
                },
                startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            MeshGradient(
                width: Self.meshColumns,
                height: Self.meshRows,
                points: Self.meshPoints.map { SIMD2(Float($0.x), Float($0.y)) },
                colors: Self.meshPoints.map { Self.color(at: $0, ground: ground, lights: lights).color },
                smoothsColors: true,
                colorSpace: .device
            )
        }
    }

    // MARK: - Actions - Mixing

    nonisolated static var meshPoints: [SIMD2<Double>] {
        (0..<meshRows).flatMap { row in
            (0..<meshColumns).map { column in
                SIMD2(Double(column) / Double(meshColumns - 1), Double(row) / Double(meshRows - 1))
            }
        }
    }

    /// The field's colors along the diagonal between two opposite lights.
    nonisolated static func diagonalStops(
        ground: OKLCHColor, lights: [OKLCHColor]
    ) -> [(color: OKLCHColor, location: Double)] {
        (0...8).map { step in
            let location = Double(step) / 8
            return (color(at: SIMD2(location, location), ground: ground, lights: lights), location)
        }
    }

    /// Where each light sits in the unit square.
    nonisolated static func anchors(count: Int) -> [SIMD2<Double>] {
        switch count {
        case 0: []
        case 1: [SIMD2(0, 0)]
        case 2: [SIMD2(0, 0), SIMD2(1, 1)]
        default: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)]
        }
    }

    /// The ground at `point` with the lights mixed in OKLab, by weights that
    /// never add up to more than the whole.
    nonisolated static func color(at point: SIMD2<Double>, ground: OKLCHColor, lights: [OKLCHColor]) -> OKLCHColor {
        let lights = Array(lights.prefix(3))
        let anchors = anchors(count: lights.count)
        var weights = anchors.map { anchor -> Double in
            let distance = ((point - anchor) * (point - anchor)).sum().squareRoot()
            let reach = max(0, 1 - distance / lightReach)
            return lightPeak * reach * reach * (3 - 2 * reach)
        }
        let total = weights.reduce(0, +)
        if total > 1 { weights = weights.map { $0 / total } }
        var lab = ground.lab * (1 - weights.reduce(0, +))
        for (light, weight) in zip(lights, weights) {
            lab += light.lab * weight
        }
        return OKLCHColor(lab: lab).mappedToSRGB
    }
}
