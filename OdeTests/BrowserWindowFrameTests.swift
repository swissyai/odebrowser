import SwiftUI
import XCTest

@testable import Ode

/// The window's frame: a Space's ground turns gently across the window
/// without costing its text any contrast, its grain is the same every
/// launch, the ring is ten points wide unless set to none, and favorites
/// rest as see-through squares on the Space's color.
@MainActor
final class BrowserWindowFrameTests: XCTestCase {
    // MARK: - Gradient

    func testTheGradientNeverTakesContrastFromTheText() {
        var checked = 0
        for hue in stride(from: 0.0, to: 360.0, by: 5) {
            for (vividness, intensity) in [(1.0, 0.5), (1.0, 1.0), (0.35, 0.35), (0.0, 0.0)] {
                for scheme in [ColorScheme.light, .dark] {
                    for increased in [false, true] {
                        for active in [true, false] {
                            let roles = SpaceColorRoles(
                                SpaceColorInputs(hue: hue, vividness: vividness, intensity: intensity),
                                colorScheme: scheme, increasedContrast: increased, isActive: active)
                            for ground in [roles.window, roles.sidebar] {
                                let lights = SpaceGroundLight.derived(over: ground, colorScheme: scheme)
                                let diagonal = BrowserSpaceGroundField.diagonalStops(ground: ground, lights: lights)
                                let shades =
                                    BrowserSpaceGroundField.meshPoints.map {
                                        BrowserSpaceGroundField.color(at: $0, ground: ground, lights: lights)
                                    } + diagonal.map(\.color)
                                for (point, shade) in shades.enumerated() {
                                    for role in [roles.text, roles.secondaryText, roles.accentText, roles.dangerText] {
                                        let plain = OKLCHColor.contrast(role, ground)
                                        XCTAssertGreaterThanOrEqual(
                                            OKLCHColor.contrast(role, shade), plain * 0.995,
                                            "hue \(hue) \(scheme) increased \(increased) at \(point)")
                                    }
                                    XCTAssertGreaterThanOrEqual(
                                        OKLCHColor.contrast(roles.text, shade), roles.floors.text - 0.01,
                                        "hue \(hue) \(scheme) increased \(increased)")
                                    checked += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 10_000)
    }

    func testAOneColorSpaceTurnsAcrossTheWindow() {
        for scheme in [ColorScheme.light, .dark] {
            let roles = SpaceColorRoles(SpaceColorInputs(hue: 190, vividness: 1, intensity: 0.5), colorScheme: scheme)
            let lights = SpaceGroundLight.derived(over: roles.window, colorScheme: scheme)
            XCTAssertEqual(lights.count, 2)
            let lead = BrowserSpaceGroundField.color(at: SIMD2(0, 0), ground: roles.window, lights: lights)
            let trail = BrowserSpaceGroundField.color(at: SIMD2(1, 1), ground: roles.window, lights: lights)
            let difference = ((lead.lab - trail.lab) * (lead.lab - trail.lab)).sum().squareRoot()
            XCTAssertGreaterThan(difference, 0.012, "\(scheme): the corners must read as a gradient")
            XCTAssertLessThan(difference, 0.06, "\(scheme): the gradient stays gentle")
        }
    }

    func testGraphiteTurnsInLightnessAlone() {
        let roles = SpaceColorRoles(.graphite, colorScheme: .light)
        for light in SpaceGroundLight.derived(over: roles.window, colorScheme: .light) {
            XCTAssertEqual(light.chroma, 0, accuracy: 0.002)
        }
    }

    // MARK: - Grain

    func testTheGrainIsTheSameEveryLaunchAndEvenlySpread() throws {
        let first = try XCTUnwrap(BrowserSpaceGrain.makeTile())
        let second = try XCTUnwrap(BrowserSpaceGrain.makeTile())
        let bytes = { (image: CGImage) -> [UInt8] in
            Array((image.dataProvider?.data as Data?) ?? Data())
        }
        XCTAssertEqual(first.width, BrowserSpaceGrain.tileSide)
        XCTAssertEqual(bytes(first), bytes(second))
        let values = bytes(first).map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        XCTAssertEqual(mean, 127.5, accuracy: 4)
        XCTAssertNotEqual(bytes(first), bytes(try XCTUnwrap(BrowserSpaceGrain.makeTile(seed: 7))))
    }

    // MARK: - Page frame

    func testPageInsetsFollowTheChosenFrameAndZeroMeansBorderless() {
        let windowRadius: CGFloat = 26
        for width in [CGFloat(3.5), CGFloat(BrowserChromeAppearance.borderWidthRange.upperBound)] {
            let appearance = BrowserChromeAppearance(borderWidth: width, windowCornerRadius: windowRadius)
            XCTAssertEqual(appearance.frameWidth, width)
            XCTAssertEqual(
                appearance.framedPageCornerRadius, windowRadius - width, "The page's corner follows the window's.")
            let hidden = appearance.pageInsets(docked: false, direction: .leftToRight)
            XCTAssertEqual(
                [hidden.top, hidden.leading, hidden.bottom, hidden.trailing], Array(repeating: width, count: 4))
            let topTabs = appearance.pageInsets(docked: false, belowTopBar: true, direction: .leftToRight)
            XCTAssertEqual(topTabs.top, 0)
            XCTAssertEqual([topTabs.leading, topTabs.bottom, topTabs.trailing], Array(repeating: width, count: 3))
        }

        let borderless = BrowserChromeAppearance(borderWidth: 0, windowCornerRadius: 26)
        XCTAssertTrue(borderless.borderless)
        XCTAssertEqual(borderless.pageCornerRadius, 0)
        let none = borderless.pageInsets(docked: false, direction: .leftToRight)
        XCTAssertEqual([none.top, none.leading, none.bottom, none.trailing], [0, 0, 0, 0])
    }

    func testThePageEdgeHoldsThreeToOneWithIncreaseContrast() {
        XCTAssertEqual(BrowserRootContentSurface<EmptyView>.increasedContrastStrokeOpacity, 0.5)
        for scheme in [ColorScheme.light, .dark] {
            let roles = SpaceColorRoles(
                SpaceColorInputs(hue: 60, vividness: 1, intensity: 1), colorScheme: scheme, increasedContrast: true)
            let ground = roles.window.srgbComponents
            let ink: SIMD3<Double> = scheme == .dark ? SIMD3(1, 1, 1) : SIMD3(0, 0, 0)
            let edge = ground * 0.5 + ink * 0.5
            XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(srgb: edge, ground), 3, "\(scheme)")
        }
    }

    // MARK: - Favorites

    func testFavoritesRestAsLightSquaresOverTheSpacesColor() {
        XCTAssertEqual(OdeInteractiveSurfaceModifier.translucentRestingOpacity(for: .light), 0.6)
        XCTAssertEqual(OdeInteractiveSurfaceModifier.translucentRestingOpacity(for: .dark), 0.08)
    }
}
