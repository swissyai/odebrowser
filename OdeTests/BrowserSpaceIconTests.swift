import SwiftUI
import XCTest

@testable import Ode

@MainActor
final class BrowserSpaceIconTests: XCTestCase {

    // MARK: - Glyphs

    func testGlyphReadsASymbolAnEmojiAndALetter() throws {
        XCTAssertEqual(BrowserSpaceGlyph(symbol: "leaf.fill"), .symbol("leaf.fill"))
        XCTAssertEqual(BrowserSpaceGlyph(symbol: BrowserIconSymbol.symbol(forEmoji: "🌸")), .emoji("🌸"))
        XCTAssertEqual(BrowserSpaceGlyph(symbol: try XCTUnwrap(BrowserIconSymbol.symbol(forLetter: "x"))), .letter("X"))
    }

    func testALetterIsStoredAsItsFirstLetterOrDigitCapitalized() {
        XCTAssertEqual(BrowserIconSymbol.symbol(forLetter: "  harmony"), "ode.letter:H")
        XCTAssertEqual(BrowserIconSymbol.symbol(forLetter: "7 days"), "ode.letter:7")
        XCTAssertEqual(BrowserIconSymbol.symbol(forLetter: "élan"), "ode.letter:É")
        XCTAssertEqual(BrowserIconSymbol.symbol(forLetter: "ß"), "ode.letter:ß")
        XCTAssertNil(BrowserIconSymbol.symbol(forLetter: "   "))
        XCTAssertNil(BrowserIconSymbol.symbol(forLetter: "🌸"))
        XCTAssertEqual(BrowserIconSymbol.letter(from: "ode.letter:H"), "H")
        XCTAssertNil(BrowserIconSymbol.letter(from: "house.fill"))
    }

    func testTheCoreKeepsALetterAndAnEmojiAsASpacesSymbol() throws {
        let store = BrowserStore(seed: .preview)
        let space = try XCTUnwrap(store.spaceModels.first)
        for symbol in [try XCTUnwrap(BrowserIconSymbol.symbol(forLetter: "q")), BrowserIconSymbol.symbol(forEmoji: "🌸")] {
            store.updateSpaceIdentity(space.id, name: space.settings.name, symbol: symbol, accent: space.settings.accent)
            XCTAssertEqual(store.spaceModel(space.id)?.settings.symbol, symbol)
        }
    }

    // MARK: - Colors

    func testTheCurrentSpacesGlyphTakesItsAccentSolid() {
        let branding = SpaceColorPreset.azure.branding
        let roles = SpaceColorRoles(branding.colorInputs, colorScheme: .light)
        let colors = BrowserSpaceIconColors(branding: branding, form: .glyph, isCurrent: true, colorScheme: .light)
        XCTAssertEqual(colors.glyph, roles.accentSolid.brandColor)
        XCTAssertNil(colors.tile)
        XCTAssertEqual(colors.emojiOpacity, 1)
    }

    func testAnotherSpacesGlyphTakesTheSecondaryTextOfTheGroundItSitsOn() {
        let branding = SpaceColorPreset.pink.branding
        let ground = SpaceColorRoles(SpaceColorPreset.azure.inputs, colorScheme: .dark)
        let colors = BrowserSpaceIconColors(
            branding: branding, form: .glyph, isCurrent: false, colorScheme: .dark, ground: ground)
        XCTAssertEqual(colors.glyph, ground.secondaryText.brandColor)
        XCTAssertEqual(colors.emojiOpacity, BrowserSpaceIconColors.quietEmojiOpacity)

        let alone = BrowserSpaceIconColors(branding: branding, form: .glyph, isCurrent: false, colorScheme: .dark)
        XCTAssertEqual(alone.glyph, SpaceColorRoles(branding.colorInputs, colorScheme: .dark).secondaryText.brandColor)
    }

    func testAGroundInTheOtherAppearanceIsIgnored() {
        let branding = SpaceColorPreset.pink.branding
        let ground = SpaceColorRoles(SpaceColorPreset.azure.inputs, colorScheme: .light)
        let colors = BrowserSpaceIconColors(
            branding: branding, form: .glyph, isCurrent: false, colorScheme: .dark, ground: ground)
        XCTAssertEqual(colors.glyph, SpaceColorRoles(branding.colorInputs, colorScheme: .dark).secondaryText.brandColor)
    }

    func testTheCurrentTileIsTheAccentSolidUnderTheLabelColor() {
        for scheme in [ColorScheme.light, .dark] {
            let branding = SpaceColorPreset.green.branding
            let roles = SpaceColorRoles(branding.colorInputs, colorScheme: scheme)
            let colors = BrowserSpaceIconColors(branding: branding, form: .tile, isCurrent: true, colorScheme: scheme)
            XCTAssertEqual(colors.tile, roles.accentSolid.brandColor)
            XCTAssertEqual(colors.glyph, roles.labelOnSolid.brandColor)
            XCTAssertGreaterThanOrEqual(OKLCHColor.contrast(roles.labelOnSolid, roles.accentSolid), 4.5)
        }
    }

    func testAnotherTileIsTheSpacesHoverTintUnderItsSecondaryText() {
        let branding = SpaceColorPreset.orange.branding
        let roles = SpaceColorRoles(branding.colorInputs, colorScheme: .light)
        let colors = BrowserSpaceIconColors(branding: branding, form: .tile, isCurrent: false, colorScheme: .light)
        XCTAssertEqual(colors.tile, roles.hover.brandColor)
        XCTAssertEqual(colors.glyph, roles.secondaryText.brandColor)
    }

    // MARK: - Presets

    func testAPresetsLookWearsItsSwatchAsItsOneColor() {
        let look = SpaceColorPreset.teal.branding
        XCTAssertEqual(Array(look.colors), [SpaceColorPreset.teal.swatch])
        XCTAssertEqual(look.iconStyle, .simpleSymbol)
        XCTAssertEqual(SpaceColorPreset.nearest(to: look.colorInputs), .teal)
    }

    func testTheNearestPresetIsGraphiteForAGraySpaceAndTheClosestHueOtherwise() {
        XCTAssertEqual(SpaceColorPreset.nearest(to: .graphite), .graphite)
        XCTAssertEqual(SpaceColorPreset.nearest(to: SpaceColorInputs(hue: 250, vividness: 0.8, intensity: 0.5)), .azure)
        XCTAssertEqual(SpaceColorPreset.nearest(to: SpaceColorInputs(hue: 15, vividness: 1, intensity: 0.5)), .red)
        XCTAssertEqual(SpaceColorPreset.nearest(to: SpaceColorInputs(hue: 355, vividness: 1, intensity: 0.5)), .pink)
    }
}
