import SwiftUI
import XCTest

@testable import Ode

final class OdeTileColorTests: XCTestCase {
    func testAWhiteSymbolKeepsItsFloorOnEveryTileInEitherAppearance() {
        let white = OKLCHColor(lightness: 1, chroma: 0, hue: 0)
        for tile in OdeTileColor.all {
            for colorScheme in [ColorScheme.light, .dark] {
                for increasedContrast in [false, true] {
                    let fill = tile.fill(colorScheme: colorScheme, increasedContrast: increasedContrast)
                    let floor = increasedContrast ? OdeTileColor.increasedSymbolContrast : OdeTileColor.symbolContrast
                    XCTAssertGreaterThanOrEqual(
                        OKLCHColor.contrast(white, fill), floor,
                        "\(tile.name), \(colorScheme), increased contrast \(increasedContrast)")
                }
            }
        }
    }
}
