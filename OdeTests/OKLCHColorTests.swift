import SwiftUI
import XCTest

@testable import Ode

/// Colour maths has one owner: every surface that checks a contrast floor
/// measures the WCAG 2 ratio of relative luminances, and the favicon palette
/// and the Space roles convert to and from OKLab with the same matrices.
final class OKLCHColorTests: XCTestCase {
    private static let samples: [SIMD3<Double>] = [
        SIMD3(1, 1, 1), SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
        SIMD3(0.188, 0.314, 0.941), SIMD3(0.941, 0.478, 0.439), SIMD3(0.467, 0.467, 0.467),
        SIMD3(0.02, 0.6, 0.35),
    ]

    func testOKLabMatchesItsReferenceValuesAndTheFaviconPaletteConvertsTheSameWay() {
        // Björn Ottosson's OKLab coordinates for white and the sRGB primaries.
        let reference: [(srgb: SIMD3<Double>, lab: SIMD3<Double>)] = [
            (SIMD3(1, 1, 1), SIMD3(1, 0, 0)),
            (SIMD3(1, 0, 0), SIMD3(0.627_955_4, 0.224_863_1, 0.125_846_3)),
            (SIMD3(0, 1, 0), SIMD3(0.866_439_6, -0.233_887_6, 0.179_498_5)),
            (SIMD3(0, 0, 1), SIMD3(0.452_013_7, -0.032_457_0, -0.311_528_1)),
        ]
        for (srgb, lab) in reference {
            assertEqual(OKLCHColor(srgbRed: srgb.x, green: srgb.y, blue: srgb.z).lab, lab, accuracy: 1e-6)
        }
        for srgb in Self.samples {
            let color = OKLCHColor(srgbRed: srgb.x, green: srgb.y, blue: srgb.z)
            let favicon = BrowserFaviconColor(red: srgb.x, green: srgb.y, blue: srgb.z)
            assertEqual(favicon.perceptualComponents, color.lab, accuracy: 1e-12)
            let back = BrowserFaviconColor(perceptualComponents: favicon.perceptualComponents)
            assertEqual(SIMD3(back.red, back.green, back.blue), srgb, accuracy: 1e-5)
            // Along pure blue's own hue the gamut's edge dips inside it, so
            // the roles draw it with less chroma.
            if srgb != SIMD3(0, 0, 1) { assertEqual(color.srgbComponents, srgb, accuracy: 1e-5) }
        }
        // A coordinate past the sRGB gamut clamps each channel; the roles'
        // conversion maps chroma down instead.
        let beyond = BrowserFaviconColor(perceptualComponents: SIMD3(0.7, 0.4, 0))
        XCTAssertEqual(beyond.red, 1, accuracy: 1e-12)
        XCTAssertEqual(beyond.green, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(beyond.blue, 0.4)
        let mapped = OKLCHColor(lab: SIMD3(0.7, 0.4, 0)).srgbComponents
        XCTAssertLessThan(mapped.x, 1)
        XCTAssertGreaterThan(mapped.y, 0)
    }

    @MainActor
    func testEveryContrastCheckMeasuresTheWCAGRatio() {
        XCTAssertEqual(OKLCHColor.contrast(srgb: SIMD3(1, 1, 1), SIMD3(0, 0, 0)), 21, accuracy: 1e-9)
        XCTAssertEqual(OKLCHColor.contrast(srgb: SIMD3(repeating: 0.467), SIMD3(1, 1, 1)), 4.48, accuracy: 0.01)
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        for first in Self.samples {
            for second in Self.samples {
                let expected = Self.wcagContrast(first, second)
                XCTAssertEqual(OKLCHColor.contrast(srgb: first, second), expected, accuracy: 1e-12)
                // The roles measure each color as drawn, after gamut mapping.
                let drawn = Self.wcagContrast(Self.color(first).srgbComponents, Self.color(second).srgbComponents)
                XCTAssertEqual(OKLCHColor.contrast(Self.color(first), Self.color(second)), drawn, accuracy: 1e-12)
                let swiftUI = Color(.sRGB, red: first.x, green: first.y, blue: first.z)
                    .contrastRatio(
                        over: Color(.sRGB, red: second.x, green: second.y, blue: second.z),
                        environment: environment)
                XCTAssertEqual(swiftUI, expected, accuracy: 1e-4)
            }
        }
        // A translucent foreground is composited over its ground by luminance.
        let halfBlack = Color.black.opacity(0.5).contrastRatio(over: .white, environment: environment)
        XCTAssertEqual(halfBlack, 1.05 / 0.55, accuracy: 1e-4)
        XCTAssertEqual(Color.white.readableForeground(colorScheme: .light), .black)
        XCTAssertEqual(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.3).readableForeground(colorScheme: .light), .white)
    }

    func testFaviconBandsAndBannerTonesReadByTheSameRatio() {
        for ground in [0.0, 0.18, 1.0] {
            for band in 0..<BrowserFaviconTone.bandCount {
                var bands = Array(repeating: 0.0, count: BrowserFaviconTone.bandCount)
                bands[band] = 1
                let tone = BrowserFaviconTone(lightnessBands: bands, meanChroma: 0, peakChroma: 0)
                let luminance = BrowserFaviconTone.luminance(ofBand: band)
                let reads = (max(luminance, ground) + 0.05) / (min(luminance, ground) + 0.05) >= 2
                XCTAssertEqual(
                    tone.readableShare(againstGroundLuminance: ground, minimumContrast: 2), reads ? 1 : 0,
                    "band \(band) on \(ground)")
            }
        }
        // Grays either side of the point where black and white text read
        // equally, at full strength and without a fade.
        for gray in stride(from: 0.30, through: 0.62, by: 0.02) {
            let palette = ColorPalette(colors: [BrandColor(red: gray, green: gray, blue: gray)])
            let level = SIMD3(repeating: gray)
            let light = Self.wcagContrast(SIMD3(1, 1, 1), level)
            let dark = Self.wcagContrast(SIMD3(0, 0, 0), level)
            XCTAssertEqual(
                palette.foregroundTone(strength: 1, readabilityFade: 0), light >= dark ? .light : .dark, "gray \(gray)")
        }
    }

    // MARK: - Helpers

    /// WCAG 2's ratio from its definition, for encoded sRGB.
    private static func wcagContrast(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func luminance(_ color: SIMD3<Double>) -> Double {
            0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func color(_ srgb: SIMD3<Double>) -> OKLCHColor {
        OKLCHColor(srgbRed: srgb.x, green: srgb.y, blue: srgb.z)
    }

    private func assertEqual(
        _ actual: SIMD3<Double>, _ expected: SIMD3<Double>, accuracy: Double, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in 0..<3 {
            XCTAssertEqual(actual[index], expected[index], accuracy: accuracy, "\(actual)", file: file, line: line)
        }
    }
}
