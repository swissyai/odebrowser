import SwiftUI
import Synchronization
import XCTest

@testable import Ode

final class SpaceColorRolesTests: XCTestCase {

    // MARK: - Conversion

    func testOKLCHConvertsToTheSRGBValueOKLCHFyiGivesForItsExample() {
        XCTAssertEqual(OKLCHColor(lightness: 0.623, chroma: 0.188, hue: 259.815).hexString, "#3B82F6")
    }

    func testSRGBRoundTripsThroughOKLCH() {
        let color = OKLCHColor(srgbRed: 0.2, green: 0.6, blue: 0.4)
        let components = color.srgbComponents
        XCTAssertEqual(components.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(components.y, 0.6, accuracy: 1e-6)
        XCTAssertEqual(components.z, 0.4, accuracy: 1e-6)
    }

    func testMaximumChromaIsTheSRGBGamutEdge() {
        XCTAssertEqual(OKLCHColor.maximumChroma(lightness: 0.5, hue: 285), 0.2922, accuracy: 0.0005)
        XCTAssertEqual(OKLCHColor.maximumChroma(lightness: 1, hue: 285), 0)
    }

    func testGamutCacheDoesNotSubstituteANearbyLightness() {
        let hue = 117.021
        let first = OKLCHColor.maximumChroma(lightness: 0.412341, hue: hue)
        let second = OKLCHColor.maximumChroma(lightness: 0.412339, hue: hue)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(OKLCHColor(lightness: 0.412339, chroma: second, hue: hue).isInSRGBGamut)
        XCTAssertEqual(OKLCHColor.maximumChroma(lightness: 0.412341, hue: hue), first)
    }

    func testGamutMappingKeepsLightnessAndHue() {
        let mapped = OKLCHColor(lightness: 0.95, chroma: 0.035, hue: 25).mappedToSRGB
        XCTAssertTrue(mapped.isInSRGBGamut)
        XCTAssertEqual(mapped.lightness, 0.95)
        XCTAssertEqual(mapped.hue, 25, accuracy: 1e-9)
        XCTAssertLessThan(mapped.chroma, 0.035)
    }

    // MARK: - Roles

    func testAzureRolesMatchTheColorStudy() {
        let azure = SpaceColorInputs(hue: 235, vividness: 1, intensity: 0.5)
        let light = SpaceColorRoles(azure, colorScheme: .light)
        let dark = SpaceColorRoles(azure, colorScheme: .dark)

        assertHex(light.sidebar, "#D7EBF8")
        // A shade under the study's #1F77A2, where white on it reaches 5:1.
        assertHex(light.accentSolid, "#1F77A1")
        assertHex(dark.sidebar, "#081923")
        assertHex(dark.accentSolid, "#59C0F8")
    }

    /// Every hue at 1 degree, the picker's chroma range, every intensity, light
    /// and dark, standard and increased contrast, active and inactive: each
    /// role keeps its floor against every ground it is drawn on, by WCAG 2.2,
    /// and its text keeps APCA Lc 60 as the second check.
    func testEveryHueChromaAppearanceAndContrastSettingKeepsItsFloors() {
        var grid: [SpaceColorInputs] = []
        for hue in stride(from: 0.0, to: 360.0, by: 1.0) {
            for vividness in [0.1, 0.5, 1] {
                for intensity in [0.5, 1] {
                    grid.append(SpaceColorInputs(hue: hue, vividness: vividness, intensity: intensity))
                }
            }
        }
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            for vividness in stride(from: 0.1, through: 1.0001, by: 0.1) {
                for intensity in [0.25, 0.75] {
                    grid.append(SpaceColorInputs(hue: hue, vividness: vividness, intensity: intensity))
                }
            }
        }
        grid += SpaceColorPreset.all.map { SpaceColorInputs(color: $0.swatch) }
        let failures = Self.failures(in: grid)
        XCTAssertTrue(
            failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(12).joined(separator: "\n"))")
    }

    func testPresetsKeepTheirFloorsAsStored() {
        let failures = Self.failures(in: SpaceColorPreset.all.map { SpaceColorInputs(color: $0.swatch) })
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// The pairs each role is drawn in, with their floors.
    nonisolated private static func failures(in grid: [SpaceColorInputs]) -> [String] {
        let found = Mutex<[String]>([])
        DispatchQueue.concurrentPerform(iterations: grid.count) { index in
            let inputs = grid[index]
            var local: [String] = []
            for scheme in [ColorScheme.light, .dark] {
                for increased in [false, true] {
                    for active in [true, false] {
                        let roles = SpaceColorRoles(
                            inputs, colorScheme: scheme, increasedContrast: increased, isActive: active)
                        let label =
                            "\(scheme) increased \(increased) active \(active) hue \(inputs.hue) vividness \(inputs.vividness) intensity \(inputs.intensity)"
                        local += check(roles, label)
                    }
                }
            }
            if !local.isEmpty { found.withLock { $0 += local } }
        }
        return found.withLock { $0 }
    }

    nonisolated private static func check(_ roles: SpaceColorRoles, _ label: String) -> [String] {
        var failures: [String] = []
        let floors = roles.floors
        func wcag(_ name: String, _ foreground: SIMD3<Double>, _ background: SIMD3<Double>, _ minimum: Double) {
            let ratio = OKLCHColor.contrast(srgb: foreground, background)
            if ratio < minimum - 1e-6 { failures.append("\(label): \(name) \(ratio) < \(minimum)") }
        }
        func apca(_ name: String, _ text: SIMD3<Double>, _ background: SIMD3<Double>) {
            let lc = OKLCHColor.apcaContrast(text: text, background: background)
            if lc < 60 { failures.append("\(label): \(name) APCA Lc \(lc) < 60") }
        }
        let sidebar = roles.sidebar.srgbComponents
        let hover = roles.hover.srgbComponents
        let selected = roles.selected.srgbComponents
        let window = roles.window.srgbComponents
        let rows = [("sidebar", sidebar), ("hover", hover), ("selected", selected)]
        for (ground, color) in rows + [("window", window)] {
            wcag("text / \(ground)", roles.text.srgbComponents, color, floors.text)
            apca("text / \(ground)", roles.text.srgbComponents, color)
        }
        for (ground, color) in rows {
            wcag("secondaryText / \(ground)", roles.secondaryText.srgbComponents, color, max(4.5, floors.secondaryText))
            apca("secondaryText / \(ground)", roles.secondaryText.srgbComponents, color)
            wcag("accentSolid / \(ground)", roles.accentSolid.srgbComponents, color, max(3, floors.accentSolid))
            wcag("dangerText / \(ground)", roles.dangerText.srgbComponents, color, max(4.5, floors.dangerText))
            apca("dangerText / \(ground)", roles.dangerText.srgbComponents, color)
            wcag("cautionSymbol / \(ground)", roles.cautionSymbol.srgbComponents, color, max(3, floors.cautionSymbol))
        }
        for (ground, color) in rows.prefix(2) {
            wcag("accentText / \(ground)", roles.accentText.srgbComponents, color, max(4.5, floors.accentText))
            apca("accentText / \(ground)", roles.accentText.srgbComponents, color)
        }
        let solid = roles.accentSolid.srgbComponents
        wcag("labelOnSolid / accentSolid", roles.labelOnSolid.srgbComponents, solid, max(4.5, floors.labelOnSolid))
        apca("labelOnSolid / accentSolid", roles.labelOnSolid.srgbComponents, solid)
        if let ring = floors.selectionRing {
            wcag("separator / sidebar", roles.separator.srgbComponents, sidebar, max(3, ring))
        }
        let fill = roles.commandBarSelection.srgbComponents
        let white = SIMD3<Double>(repeating: 1)
        let opacity = roles.commandBarSecondaryLabelOpacity
        let secondaryLabel = white * opacity + fill * (1 - opacity)
        wcag("white / command bar selection", white, fill, max(4.5, floors.commandBarLabel))
        apca("white / command bar selection", white, fill)
        wcag("secondary label / command bar selection", secondaryLabel, fill, max(4.5, floors.commandBarSecondaryLabel))
        apca("secondary label / command bar selection", secondaryLabel, fill)
        wcag("keycap glyph / command bar keycap", white, white * 0.1 + fill * 0.9, 4.5)
        if !roles.sidebar.isInSRGBGamut { failures.append("\(label): sidebar out of gamut") }
        return failures
    }

    func testRolesMoveOnlyAsFarAsTheirFloorsAsk() {
        // Azure in light passes at its ladder lightness, so it keeps the
        // color study's values; green is the hue that moves.
        let azure = SpaceColorRoles(SpaceColorInputs(hue: 235, vividness: 1, intensity: 0.5), colorScheme: .light)
        XCTAssertEqual(azure.accentText.lightness, 0.47, accuracy: 0.012)
        let green = SpaceColorRoles(SpaceColorInputs(hue: 143, vividness: 1, intensity: 0.5), colorScheme: .light)
        XCTAssertLessThan(green.accentText.lightness, 0.47)
        XCTAssertGreaterThan(green.accentText.lightness, 0.45)
        XCTAssertEqual(OKLCHColor.contrast(green.accentText, green.hover), 5, accuracy: 0.05)
    }

    func testIncreasedContrastRingsTheSelectedRow() {
        for hue in stride(from: 0.0, to: 360.0, by: 15.0) {
            for scheme in [ColorScheme.light, .dark] {
                let inputs = SpaceColorInputs(hue: hue, vividness: 1, intensity: 0.5)
                let standard = SpaceColorRoles(inputs, colorScheme: scheme)
                let increased = SpaceColorRoles(inputs, colorScheme: scheme, increasedContrast: true)
                XCTAssertLessThan(OKLCHColor.contrast(standard.separator, standard.sidebar), 3)
                XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(increased.separator, increased.sidebar), 3.2 - 1e-6)
            }
        }
    }

    func testPanelDetailKeepsItsContrastOnOdesPanels() {
        let light: [SIMD3<Double>] = [[1, 1, 1], [0.984, 0.984, 0.984], [0.945, 0.945, 0.945]]
        let dark: [SIMD3<Double>] = [[0.184, 0.184, 0.192], [0.173, 0.173, 0.180], [0.137, 0.137, 0.137]]
        for (scheme, panels) in [(ColorScheme.light, light), (.dark, dark)] {
            for increased in [false, true] {
                let detail = OdePanelDetailStyle.color(colorScheme: scheme, increasedContrast: increased).srgbComponents
                for panel in panels {
                    XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(srgb: detail, panel), increased ? 7 : 4.5)
                    XCTAssertGreaterThanOrEqual(OKLCHColor.apcaContrast(text: detail, background: panel), 60)
                }
            }
        }
    }

    func testFolderFillsKeepTheSpacesTextReadable() {
        for choice in BrowserFolderColorPalette.choices {
            for scheme in [ColorScheme.light, .dark] {
                for increased in [false, true] {
                    for hue in [0.0, 145, 235, 300] {
                        let roles = SpaceColorRoles(
                            SpaceColorInputs(hue: hue, vividness: 1, intensity: 0.5), colorScheme: scheme,
                            increasedContrast: increased)
                        for strength in [0.0, 0.5, 1] {
                            let fill = BrowserFolderFill.color(choice.value, strength: strength, roles: roles)
                            let label = "\(choice.title) \(scheme) \(strength) hue \(hue) increased \(increased)"
                            XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(roles.text, fill), 7 - 1e-6, label)
                            XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(roles.secondaryText, fill), 5 - 1e-6, label)
                        }
                    }
                }
            }
        }
    }

    /// A hierarchical `.secondary` on a `Text` draws the primary text at half
    /// strength; the secondary role draws its own color.
    @MainActor
    func testSecondaryTextOnASpaceGroundDrawsTheRole() throws {
        let inputs = SpaceColorInputs(hue: 235, vividness: 1, intensity: 0.5)
        let roles = SpaceColorRoles(inputs, colorScheme: .light)
        var branding = SpaceBranding.neutral
        branding.colors = ColorPalette(colors: [swatch(hue: 235)])
        let view = Text(Image(systemName: "square.fill"))
            .font(.system(size: 48))
            .foregroundStyle(SpaceRoleStyle.secondaryText)
            .padding(8)
            .background(Color.white)
            .spaceColorRoles(for: branding)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let drawn = try XCTUnwrap(Self.centerColor(of: image))
        let expected = roles.secondaryText.srgbComponents
        for (value, wanted) in zip([drawn.x, drawn.y, drawn.z], [expected.x, expected.y, expected.z]) {
            XCTAssertEqual(value, wanted, accuracy: 3.0 / 255)
        }
    }

    private static func centerColor(of image: CGImage) -> SIMD3<Double>? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        let center = CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)
        guard let pixel = image.cropping(to: center) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return SIMD3(Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255)
    }

    func testIncreasedContrastWidensTheTextRoles() {
        let inputs = SpaceColorInputs(hue: 145, vividness: 1, intensity: 0.5)
        for scheme in [ColorScheme.light, .dark] {
            let standard = SpaceColorRoles(inputs, colorScheme: scheme)
            let increased = SpaceColorRoles(inputs, colorScheme: scheme, increasedContrast: true)
            XCTAssertGreaterThan(
                OKLCHColor.contrast(increased.secondaryText, increased.sidebar),
                OKLCHColor.contrast(standard.secondaryText, standard.sidebar))
            XCTAssertEqual(increased.sidebar, standard.sidebar)
        }
    }

    func testAnInactiveWindowHalvesItsGroundAndSolidChroma() {
        let inputs = SpaceColorInputs(hue: 25, vividness: 1, intensity: 0.5)
        let active = SpaceColorRoles(inputs, colorScheme: .light)
        let inactive = SpaceColorRoles(inputs, colorScheme: .light, isActive: false)
        XCTAssertEqual(inactive.sidebar.lightness, active.sidebar.lightness)
        XCTAssertEqual(inactive.sidebar.chroma, active.sidebar.chroma / 2, accuracy: 1e-9)
        XCTAssertEqual(inactive.accentSolid.chroma, active.accentSolid.chroma / 2, accuracy: 1e-9)
    }

    func testGraphiteCarriesNoColor() {
        for scheme in [ColorScheme.light, .dark] {
            let roles = SpaceColorRoles(.graphite, colorScheme: scheme)
            for role in [roles.window, roles.sidebar, roles.hover, roles.text, roles.accentSolid, roles.labelOnSolid] {
                XCTAssertEqual(role.chroma, 0, "\(scheme)")
            }
        }
    }

    // MARK: - Inputs

    func testAStoredColorGivesItsHueAndVividness() {
        let azure = SpaceColorInputs(color: swatch(hue: 235))
        XCTAssertEqual(azure.hue, 235, accuracy: 1)
        XCTAssertEqual(azure.vividness, 1, accuracy: 0.03)
        XCTAssertEqual(azure.intensity, SpaceColorInputs.defaultIntensity)

        let muted = SpaceColorInputs(color: swatch(hue: 80, vividness: 0.35))
        XCTAssertEqual(muted.hue, 80, accuracy: 2)
        XCTAssertEqual(muted.vividness, 0.35, accuracy: 0.03)
    }

    func testAGrayColorIsGraphite() {
        XCTAssertEqual(SpaceColorInputs(color: BrandColor(red: 0.5, green: 0.5, blue: 0.5)), .graphite)
        XCTAssertEqual(SpaceColorInputs(color: swatch(hue: 0, vividness: 0)), .graphite)
    }

    func testABrandingReadsItsMostColorfulColor() {
        var branding = SpaceBranding.neutral
        XCTAssertEqual(branding.colorInputs, .graphite)

        branding.colors = ColorPalette(colors: [swatch(hue: 300)])
        XCTAssertEqual(branding.colorInputs.hue, 300, accuracy: 1)

        branding.colors = ColorPalette(colors: [
            BrandColor(red: 0.118, green: 0.157, blue: 0.2), swatch(hue: 235),
            BrandColor(red: 0.9, green: 0.9, blue: 0.92),
        ])
        XCTAssertEqual(branding.colorInputs.hue, 235, accuracy: 1)
        XCTAssertEqual(branding.colorInputs.vividness, 1, accuracy: 0.03)
    }

    // MARK: - Ground lights

    func testGroundLightsKeepTheGroundsLightnessAndStayInGamut() {
        let ground = SpaceColorRoles(SpaceColorInputs(hue: 25, vividness: 1, intensity: 0.5), colorScheme: .light)
            .sidebar
        let lights = [205.0, 300].map {
            SpaceGroundLight.color(swatch(hue: $0), over: ground, intensity: 0.5, isActive: true)
        }
        for point in BrowserSpaceGroundField.meshPoints {
            let mixed = BrowserSpaceGroundField.color(at: point, ground: ground, lights: lights)
            XCTAssertEqual(mixed.lightness, ground.lightness, accuracy: 1e-9)
            XCTAssertTrue(mixed.isInSRGBGamut)
        }
    }

    func testOnlyAGradientWithSeveralColorsLightsItsGround() {
        var branding = SpaceBranding.neutral
        branding.colors = ColorPalette(colors: [swatch(hue: 25), swatch(hue: 190)])
        branding.themeMode = .banner
        XCTAssertTrue(branding.groundLightColors.isEmpty)
        branding.themeMode = .gradient
        XCTAssertEqual(branding.groundLightColors.count, 2)
        branding.colors = ColorPalette(colors: [swatch(hue: 25)])
        XCTAssertTrue(branding.groundLightColors.isEmpty)
    }

    // MARK: - Presets

    func testPresetsWearTheirOwnInputs() {
        XCTAssertEqual(SpaceColorPreset.all.count, 10)
        for preset in SpaceColorPreset.all {
            let inputs = SpaceColorInputs(color: preset.swatch)
            if preset == .graphite {
                XCTAssertEqual(inputs, .graphite)
            } else {
                XCTAssertEqual(inputs.hue, preset.inputs.hue, accuracy: 1, preset.name)
                XCTAssertEqual(inputs.vividness, preset.inputs.vividness, accuracy: 0.03, preset.name)
            }
        }
    }

    // MARK: - Helpers

    /// A stored color of `hue` as vivid as a swatch, or less.
    private func swatch(hue: Double, vividness: Double = 1) -> BrandColor {
        OKLCHColor(
            lightness: SpaceColorInputs.swatchLightness,
            chroma: vividness * SpaceColorInputs.swatchChroma(hue: hue), hue: hue
        ).brandColor
    }

    private func assertHex(
        _ color: OKLCHColor, _ expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = color.srgbComponents
        let target = [1, 3, 5].map { offset -> Double in
            let start = expected.index(expected.startIndex, offsetBy: offset)
            return Double(Int(expected[start..<expected.index(start, offsetBy: 2)], radix: 16)!) / 255
        }
        for (value, wanted) in zip([actual.x, actual.y, actual.z], target) {
            XCTAssertEqual(
                value, wanted, accuracy: 1.0 / 255 + 1e-9, "\(color.hexString) for \(expected)", file: file, line: line)
        }
    }
}
