import UIKit
import XCTest

@testable import OdeMobile

@MainActor
final class MobileCommandPaletteEditingTests: XCTestCase {
    func testEveryPresentationUsesNormalTextInputAndSubmitsSearchesAndURLs() async {
        for presentation in [BrowserCommandPalettePresentation.embedded, .overlay] {
            var openedURLs: [URL] = []
            let fixture = makeEditor(presentation: presentation) { url in
                openedURLs.append(url)
                return true
            }
            XCTAssertEqual(fixture.field.keyboardType, .default)
            XCTAssertNil(fixture.field.textContentType)
            fixture.field.insertText("kroger pharmacy")
            fixture.coordinator.editingChanged()
            await fixture.model.waitForPendingResults()
            XCTAssertEqual(fixture.model.query, "kroger pharmacy")
            XCTAssertNil(fixture.model.urlCompletion)
            XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(fixture.field))
            XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://www.google.com/search?q=kroger%20pharmacy"])
            fixture.field.selectedTextRange = fixture.field.textRange(
                from: fixture.field.beginningOfDocument, to: fixture.field.endOfDocument)
            fixture.field.insertText("example.org")
            fixture.coordinator.editingChanged()
            await fixture.model.waitForPendingResults()
            XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(fixture.field))
            XCTAssertEqual(openedURLs.last?.absoluteString, "https://example.org")
        }
    }

    /// A Start Page appearing never puts the keyboard up by itself: its field
    /// takes focus once for each request the person made. The overlay
    /// Command Bar, which only opens on request, always does.
    func testTheStartPageFieldTakesFocusOnlyForARequest() {
        let grant = MobileCommandPaletteFocusGrant()
        XCTAssertFalse(grant.takesFocus(presentation: .embedded))
        XCTAssertTrue(grant.takesFocus(presentation: .overlay))

        grant.grant()
        XCTAssertTrue(grant.takesFocus(presentation: .embedded))
        XCTAssertFalse(grant.takesFocus(presentation: .embedded))
    }

    /// The row above the keyboard types the pieces of an address a phone
    /// keyboard hides, without doubling a dot or slash already typed.
    func testKeyboardShortcutsTypeAddressPiecesWithoutDoublingThem() {
        XCTAssertEqual(MobileAddressKeyboardShortcut.dotCom.applied(to: "apple"), "apple.com")
        XCTAssertEqual(MobileAddressKeyboardShortcut.dotCom.applied(to: "apple."), "apple.com")
        XCTAssertEqual(MobileAddressKeyboardShortcut.slash.applied(to: "apple.com"), "apple.com/")
        XCTAssertEqual(MobileAddressKeyboardShortcut.slash.applied(to: "apple.com/"), "apple.com/")
        XCTAssertEqual(MobileAddressKeyboardShortcut.dotCom.applied(to: ""), ".com")
    }

    func testNativeFieldAcceptsCompletionWithoutNavigationAndProvidesTabAction() async throws {
        for presentation in [BrowserCommandPalettePresentation.embedded, .overlay] {
            let fixture = makeEditor(presentation: presentation)
            let field = fixture.field
            field.insertText("exa")
            fixture.coordinator.editingChanged()
            await fixture.model.waitForPendingResults()
            XCTAssertEqual(field.text, "exa")
            XCTAssertEqual(fixture.model.urlCompletion?.completedQuery, "example.com")
            XCTAssertEqual(field.accessibilityLabel, "Command Palette")
            XCTAssertEqual(field.accessibilityIdentifier, "command-palette-field")
            XCTAssertTrue(
                field.keyCommands?.contains { $0.input == "\t" && $0.discoverabilityTitle == "Complete or Search Site" }
                    == true)
            let rightArrow = try XCTUnwrap(field.keyCommands?.first { $0.input == UIKeyCommand.inputRightArrow })
            XCTAssertEqual(rightArrow.modifierFlags, [])
            field.perform(rightArrow.action, with: rightArrow)
            XCTAssertEqual(field.text, "example.com")
            XCTAssertEqual(fixture.model.query, "example.com")
            XCTAssertEqual(field.autocorrectionType, .no)
            XCTAssertTrue(field.adjustsFontForContentSizeCategory)
        }
    }

    func testKeyboardAccessoryEditsTheNativeSelectionAndUpdatesTheQueryWithoutNavigating() throws {
        let fixture = makeEditor()
        let field = fixture.field
        field.insertText("http://127.0.0.1/example.")
        fixture.coordinator.editingChanged()
        fixture.coordinator.insertAddressFragment(.dotCom)
        fixture.coordinator.insertAddressFragment(.slash)
        fixture.coordinator.insertAddressFragment(.slash)
        XCTAssertEqual(field.text, "http://127.0.0.1/example.com/")
        XCTAssertEqual(fixture.model.query, field.text)

        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 24))
        let end = try XCTUnwrap(field.position(from: start, offset: 5))
        field.selectedTextRange = field.textRange(from: start, to: end)
        fixture.coordinator.insertAddressFragment(.dotCom)
        XCTAssertEqual(field.text, "http://127.0.0.1/example.com")
        XCTAssertEqual(fixture.model.query, field.text)
    }

    func testNativePasteInsertsAtTheSelectionAndUpdatesTheQueryWithoutNavigating() throws {
        let fixture = makeEditor()
        fixture.field.insertText("prefix old suffix")
        fixture.coordinator.editingChanged()
        let start = try XCTUnwrap(fixture.field.position(from: fixture.field.beginningOfDocument, offset: 7))
        let end = try XCTUnwrap(fixture.field.position(from: start, offset: 3))
        fixture.field.selectedTextRange = fixture.field.textRange(from: start, to: end)

        fixture.coordinator.insertPastedText("new")
        XCTAssertEqual(fixture.field.text, "prefix new suffix")
        XCTAssertEqual(fixture.model.query, "prefix new suffix")

        let committedQuery = fixture.model.query
        fixture.field.setMarkedText("composing", selectedRange: NSRange(location: 0, length: 4))
        fixture.coordinator.editingChanged()
        XCTAssertNotNil(fixture.field.markedTextRange)
        let composedText = fixture.field.text
        fixture.coordinator.insertPastedText("must not replace composition")
        XCTAssertEqual(fixture.field.text, composedText)
        XCTAssertEqual(fixture.model.query, committedQuery)

        fixture.field.unmarkText()
        fixture.coordinator.editingChanged()
        XCTAssertNil(fixture.field.markedTextRange)
        XCTAssertEqual(fixture.field.text, composedText)
        XCTAssertEqual(fixture.model.query, composedText)
    }

    func testNativeSelectionAndMarkedTextSuppressCompletion() async throws {
        for presentation in [BrowserCommandPalettePresentation.embedded, .overlay] {
            let fixture = makeEditor(presentation: presentation)
            let field = fixture.field
            field.insertText("exa")
            fixture.coordinator.editingChanged()
            await fixture.model.waitForPendingResults()
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            fixture.coordinator.editingChanged()
            XCTAssertNil(fixture.model.urlCompletion)
            XCTAssertFalse(field.keyCommands?.contains { $0.input == UIKeyCommand.inputRightArrow } == true)
            XCTAssertFalse(fixture.model.acceptURLCompletion())
            field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
            field.setMarkedText("m", selectedRange: NSRange(location: 1, length: 0))
            fixture.coordinator.editingChanged()
            XCTAssertNotNil(field.markedTextRange)
            XCTAssertNil(fixture.model.urlCompletion)
            XCTAssertFalse(fixture.model.acceptURLCompletion())
            XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(field))
        }
    }

    private func makeEditor(
        presentation: BrowserCommandPalettePresentation = .overlay,
        openURL: @escaping (URL) -> Bool = { _ in
            XCTFail("Unexpected navigation")
            return false
        }
    ) -> (
        field: BrowserPlatformCommandPaletteField.CompletionField,
        coordinator: BrowserPlatformCommandPaletteField.Coordinator, model: BrowserCommandPaletteModel
    ) {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = SpaceState.Seed(name: "Test", symbol: "globe", accent: .indigo, tabs: [tab])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, isOnline: { false }, lookUpDefinition: { _ in nil },
                fetchWebSummary: { _ in nil }),
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in
                XCTFail("Unexpected navigation")
                return false
            },
            openURL: { _, url, _ in openURL(url) }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: presentation, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        return (field, coordinator, model)
    }
}
