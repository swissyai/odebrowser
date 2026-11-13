import CoreGraphics
import Foundation
import XCTest

@testable import Ode

final class BrowserFaviconToneTests: XCTestCase {
    private let darkGround = TabFaviconMetrics.darkGroundLuminance
    private let lightGround = TabFaviconMetrics.lightGroundLuminance

    func testBlackMarkIsInvertedOnDarkAndLeftAloneOnLight() throws {
        let analysis = BrowserFaviconAnalysis(image: try mark(red: 0, green: 0, blue: 0))
        let tone = try XCTUnwrap(analysis.tone)
        XCTAssertTrue(tone.isMonochrome)
        XCTAssertNotNil(analysis.invertedImage)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: tone, groundLuminance: darkGround), .inverted)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: tone, groundLuminance: lightGround), .asIs)
    }

    func testWhiteMarkIsInvertedOnLightAndLeftAloneOnDark() throws {
        let tone = try XCTUnwrap(BrowserFaviconAnalysis(image: try mark(red: 1, green: 1, blue: 1)).tone)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: tone, groundLuminance: lightGround), .inverted)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: tone, groundLuminance: darkGround), .asIs)
    }

    func testDarkColorfulIconIsPlatedOnDarkWithoutRecoloring() throws {
        let analysis = BrowserFaviconAnalysis(image: try mark(red: 0.10, green: 0.12, blue: 0.36))
        let tone = try XCTUnwrap(analysis.tone)
        XCTAssertFalse(tone.isMonochrome)
        XCTAssertNil(analysis.invertedImage)
        XCTAssertEqual(
            BrowserFaviconTreatment.choose(for: tone, groundLuminance: darkGround), .plated(lightPlate: true))
    }

    func testReadableIconsAreLeftAlone() throws {
        let red = try XCTUnwrap(BrowserFaviconAnalysis(image: try mark(red: 0.9, green: 0.22, blue: 0.21)).tone)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: red, groundLuminance: darkGround), .asIs)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: red, groundLuminance: lightGround), .asIs)

        // A black glyph on its own white plate reads on both grounds.
        let plated = try XCTUnwrap(BrowserFaviconAnalysis(image: try platedGlyph()).tone)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: plated, groundLuminance: darkGround), .asIs)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: plated, groundLuminance: lightGround), .asIs)
    }

    func testEmptyIconIsLeftAlone() throws {
        let empty = try XCTUnwrap(context(side: 32)?.makeImage())
        let tone = try XCTUnwrap(BrowserFaviconAnalysis(image: empty).tone)
        XCTAssertEqual(BrowserFaviconTreatment.choose(for: tone, groundLuminance: darkGround), .asIs)
    }

    func testInvertedCopyKeepsOpacityAndFlipsColor() throws {
        let inverted = try XCTUnwrap(BrowserFaviconAnalysis.inverted(try mark(red: 0, green: 0, blue: 0)))
        let tone = try XCTUnwrap(BrowserFaviconAnalysis.tone(of: inverted))
        // The mark is now white, so it reads on dark and not on light.
        XCTAssertGreaterThan(
            tone.readableShare(againstGroundLuminance: darkGround, minimumContrast: 2), 0.9)
        XCTAssertLessThan(tone.readableShare(againstGroundLuminance: lightGround, minimumContrast: 2), 0.1)
    }

    func testAnalysisIsMadeOnceAndKeptWithTheImage() async throws {
        let image = try mark(red: 0, green: 0, blue: 0)
        let decodes = DecodeCounter()
        let cache = BrowserFaviconImageCache(decode: { _, _ in
            decodes.increment()
            return image
        })
        let payload = Data([0x0D, 0xE0])
        let hadAnalysisBefore = await cache.hasAnalysis(for: payload, maximumPixelSize: 64)
        XCTAssertFalse(hadAnalysisBefore)
        let firstValue = await cache.decodedImage(for: payload, maximumPixelSize: 64)
        let first = try XCTUnwrap(firstValue)
        let hasAnalysisAfter = await cache.hasAnalysis(for: payload, maximumPixelSize: 64)
        XCTAssertTrue(hasAnalysisAfter)
        let secondValue = await cache.decodedImage(for: payload, maximumPixelSize: 64)
        let second = try XCTUnwrap(secondValue)
        XCTAssertTrue(first.image === second.image)
        XCTAssertEqual(first.analysis.tone, second.analysis.tone)
        XCTAssertEqual(decodes.count, 1)
    }

    func testDeclaredAppearanceVariantsAreRankedForThePage() {
        let dark = "(prefers-color-scheme: dark)"
        let light = "(prefers-color-scheme:light)"
        XCTAssertEqual(BrowserFaviconCapture.appearanceFit(media: dark, prefersDark: true), 2)
        XCTAssertEqual(BrowserFaviconCapture.appearanceFit(media: dark, prefersDark: false), 0)
        XCTAssertEqual(BrowserFaviconCapture.appearanceFit(media: light, prefersDark: false), 2)
        XCTAssertEqual(BrowserFaviconCapture.appearanceFit(media: "", prefersDark: true), 1)
        XCTAssertEqual(BrowserFaviconCapture.appearanceFit(media: nil, prefersDark: false), 1)
    }

    @MainActor
    func testPageDiscoveryPrefersTheVariantForItsAppearance() throws {
        let page = try XCTUnwrap(URL(string: "https://example.com/"))
        let value: [String: Any] = [
            "icons": [
                ["url": "/light.png", "rel": "icon", "sizes": "32x32", "media": "(prefers-color-scheme: light)"],
                ["url": "/dark.png", "rel": "icon", "sizes": "32x32", "media": "(prefers-color-scheme: dark)"],
            ],
            "manifests": [],
        ]
        XCTAssertEqual(
            BrowserFaviconCapture.discovery(from: value, pageURL: page, prefersDark: true).iconURLs.first?.path,
            "/dark.png")
        XCTAssertEqual(
            BrowserFaviconCapture.discovery(from: value, pageURL: page, prefersDark: false).iconURLs.first?.path,
            "/light.png")
    }

    // MARK: - Fixtures

    private func context(side: Int) -> CGContext? {
        CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// A filled disc in one color on a clear ground, like a site's logo mark.
    private func mark(red: Double, green: Double, blue: Double) throws -> CGImage {
        let context = try XCTUnwrap(context(side: 64))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fillEllipse(in: CGRect(x: 8, y: 8, width: 48, height: 48))
        return try XCTUnwrap(context.makeImage())
    }

    /// A black square glyph on a white rounded plate.
    private func platedGlyph() throws -> CGImage {
        let context = try XCTUnwrap(context(side: 64))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 18, y: 18, width: 28, height: 28))
        return try XCTUnwrap(context.makeImage())
    }
}

private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
