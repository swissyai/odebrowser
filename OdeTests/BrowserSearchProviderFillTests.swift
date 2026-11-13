import XCTest

@testable import Ode

@MainActor
final class BrowserSearchProviderFillTests: XCTestCase {
    func testThePillTextReadsAtTheMinimumContrastOnEveryBrand() {
        for provider in BuiltInSearchProvider.all {
            let fill = BrowserSearchProviderFill(brand: provider.color)
            XCTAssertGreaterThanOrEqual(
                fill.contrast, BrowserSearchProviderFill.minimumContrast, "\(provider.title) \(fill.fill.hexString)")
        }
        // Mid grays read under neither white nor near-black text until their
        // lightness moves.
        for gray in stride(from: 0.30, through: 0.70, by: 0.02) {
            let fill = BrowserSearchProviderFill(brand: BrandColor(red: gray, green: gray, blue: gray, alpha: 1))
            XCTAssertGreaterThanOrEqual(fill.contrast, BrowserSearchProviderFill.minimumContrast, "gray \(gray)")
        }
    }

    func testYouTubeRedKeepsWhiteTextWithASmallDarkening() {
        let brand = OKLCHColor(BuiltInSearchProvider.youTube.color)
        let fill = BrowserSearchProviderFill(brand: BuiltInSearchProvider.youTube.color)

        XCTAssertTrue(fill.usesLightText)
        XCTAssertLessThan(fill.fill.lightness, brand.lightness)
        XCTAssertLessThanOrEqual(brand.lightness - fill.fill.lightness, BrowserSearchProviderFill.maximumDarkening)
        XCTAssertEqual(fill.fill.hue, brand.hue, accuracy: 0.5)
    }

    func testALightBrandTakesDarkTextAndKeepsItsColor() {
        let brand = BuiltInSearchProvider.imDb.color
        let fill = BrowserSearchProviderFill(brand: brand)

        XCTAssertFalse(fill.usesLightText)
        XCTAssertEqual(fill.fill.hexString, OKLCHColor(brand).hexString)
    }
}
