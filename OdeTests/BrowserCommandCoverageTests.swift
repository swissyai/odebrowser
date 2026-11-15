import AppKit
import SwiftUI
import XCTest

@testable import Ode

/// Every command the core names runs in the Mac shell, and every way the
/// core says a palette row activates has a way to run it. A kind left out
/// would quietly never be offered or never run.
@MainActor
final class BrowserCommandCoverageTests: XCTestCase {
    func testDeferredQueryFocusPreservesTypedProviderAndDeliberateSelection() async throws {
        let browser = BrowserStore(seed: .preview)
        BrowserSearchCatalog(core: browser.core).setEnabled(.chatGPT, true)
        var dismissed = false
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.shownSpace, selectedTabID: browser.shownTab?.id, initialQuery: "",
            commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, lookUpDefinition: { _ in nil }, fetchWebSummary: { _ in nil }),
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false }, openURL: { _, _, _ in false },
            dismiss: { dismissed = true })
        let intent = DeferredPaletteFocus()
        let host = NSHostingView(rootView: DeferredPaletteFocusSurface(model: model, intent: intent))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            intent.request = nil
            intent.setEnabled = nil
            model.stop()
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        for (letter, code) in [("c", 8), ("h", 4), ("a", 0), ("t", 17), ("g", 5), ("p", 35), ("t", 17)] {
            sendText(letter, keyCode: UInt16(code), to: window)
        }
        XCTAssertEqual(model.query, "chatgpt")
        // This is the real SearchField's deferred focus input, ordered after
        // native typing. It is not a full-app timing reproduction.
        try XCTUnwrap(intent.request)()
        host.layoutSubtreeIfNeeded()
        await model.waitForPendingResults()
        await committedNativeFrame()
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertTrue(model.completionEditing.isAtEnd)
        XCTAssertEqual(model.providerOffer?.builtIn, .chatGPT)
        sendText("\t", keyCode: 48, to: window)
        XCTAssertEqual(model.activeProvider?.builtIn, .chatGPT)
        sendText("\u{1b}", keyCode: 53, to: window)
        XCTAssertNil(model.activeProvider)
        XCTAssertFalse(dismissed)
        editor.insertText("chatgpt", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.selectAll(nil)
        await model.waitForPendingResults()
        await committedNativeFrame()
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 7))
        XCTAssertNil(model.providerOffer, "A deliberate selection still belongs to the person.")
        let field = try XCTUnwrap(paletteCoordinator(in: window)?.field)
        try XCTUnwrap(intent.setEnabled)(false)
        host.layoutSubtreeIfNeeded()
        await committedNativeFrame()
        XCTAssertFalse(field.isEditable)
        XCTAssertFalse(window.firstResponder === editor)
        try XCTUnwrap(intent.request)()
        await committedNativeFrame()
        XCTAssertFalse(window.firstResponder === editor, "An inactive field cannot take a pending focus request.")
        try XCTUnwrap(intent.setEnabled)(true)
        host.layoutSubtreeIfNeeded()
        await committedNativeFrame()
        XCTAssertEqual(model.query, "chatgpt")
        XCTAssertTrue((window.firstResponder as? NSTextView)?.delegate is BrowserPlatformCommandPaletteField.Field)
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        sendText("\u{1b}", keyCode: 53, to: window)
        XCTAssertTrue(dismissed, "After leaving scope, native Escape closes the overlay.")
    }

    private func committedNativeFrame() async {
        let committed = expectation(description: "Deferred native focus frame committed")
        BrowserMoments.shared.afterNextCommit { DispatchQueue.main.async { committed.fulfill() } }
        await fulfillment(of: [committed], timeout: 2)
    }

    func testOpeningTheCommandBarOwnsTheNativeEditorBeforeTheFollowingTextEvent() async throws {
        let application = try BrowserMacApplication()
        let engine = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: engine)
        windows.open(.initial, activation: .background)
        defer {
            for (_, window) in windows.openWindows { window.close() }
            withExtendedLifetime(engine) {}
        }
        let context = try XCTUnwrap(windows.lastUsedContext)
        let window = try XCTUnwrap(windows.window(for: context.windowID))
        _ = try XCTUnwrap(context.browser.openGettingStarted())
        context.pages.select()
        let actions = windows.actions(in: context)
        for command in [ShortcutCommand.newTab, .openLocation] {
            actions.perform(.newTab)
            for _ in 0..<100 {
                window.contentView?.layoutSubtreeIfNeeded()
                if paletteCoordinator(in: window) != nil { break }
                await Task.yield()
            }
            let previous = try XCTUnwrap(window.firstResponder as? NSTextView)
            previous.insertText("previous", replacementRange: NSRange(location: NSNotFound, length: 0))
            let oldModel = try XCTUnwrap(paletteCoordinator(in: window)).model
            XCTAssertEqual(oldModel.query, "previous")
            context.chrome.dismissCommandPalette()
            let keyWindow = NSApp.keyWindow
            XCTAssertTrue(actions.canPerform(command))
            actions.perform(command)
            // The next native text event can precede SwiftUI's idle render. No
            // manual layout or focus wait is allowed between the command and m.
            sendText("m", keyCode: 46, to: window)
            window.contentView?.layoutSubtreeIfNeeded()
            for (letter, code) in [
                ("y", 16), ("a", 0), ("s", 1), ("s", 1), ("i", 34), ("s", 1), ("t", 17), ("a", 0), ("n", 45), ("t", 17),
            ] {
                sendText(letter, keyCode: UInt16(code), to: window)
            }
            let current = try XCTUnwrap(paletteCoordinator(in: window)).model
            XCTAssertFalse(current === oldModel)
            XCTAssertEqual(current.query, "myassistant")
            XCTAssertEqual((window.firstResponder as? NSTextView)?.string, "myassistant")
            XCTAssertTrue(windows.window(for: context.windowID) === window)
            XCTAssertEqual(context.browser.shownTab?.nativeTabContent, .gettingStarted)
            XCTAssertEqual(windows.openWindows.count, 1)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
            context.chrome.dismissCommandPalette()
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func paletteCoordinator(in window: NSWindow) -> BrowserPlatformCommandPaletteField.Coordinator? {
        guard let editor = window.firstResponder as? NSTextView,
            let field = editor.delegate as? BrowserPlatformCommandPaletteField.Field
        else { return nil }
        return field.delegate as? BrowserPlatformCommandPaletteField.Coordinator
    }

    private func sendText(_ text: String, keyCode: UInt16, to window: NSWindow) {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: keyCode)
        else { return XCTFail("A native text event is required") }
        window.sendEvent(event)
    }

    func testEveryCommandTheCoreNamesRunsInTheMacShell() {
        let missing = ShortcutCommand.all.filter { BrowserMacCommand.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }

    func testEveryActivationTheCoreNamesRunsInThePalette() {
        let missing = PaletteActivation.all.filter { BrowserCommandPaletteActivation.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }

    /// With every browser window closed, New Tab opens a window and starts
    /// the new tab there, as other Mac browsers do, rather than doing nothing
    /// while the app stays in front with no window.
    func testNewTabWithNoBrowserWindowOpensOneShowingItsCommandBar() throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let before = Set(NSApp.windows.map(\.windowNumber))
        defer {
            for window in NSApp.windows where !before.contains(window.windowNumber) { window.close() }
            withExtendedLifetime(host) {}
        }
        XCTAssertNil(windows.lastUsedContext)
        let windowless = try XCTUnwrap(BrowserMacCommand.newTab.withoutWindow)
        XCTAssertTrue(windowless.isAvailable(windows))

        windowless.run(windows)

        let context = try XCTUnwrap(windows.lastUsedContext)
        if context.browser.shownTab?.surface == .startPage {
            XCTAssertGreaterThan(context.chrome.startPageFocusRequest, 0)
        } else {
            XCTAssertEqual(context.chrome.commandPaletteMode, .newTab)
        }
        XCTAssertFalse(windowless.isAvailable(windows))
    }
}

@MainActor
private final class DeferredPaletteFocus {
    var request: (() -> Void)?
    var setEnabled: ((Bool) -> Void)?
}

@MainActor
private struct DeferredPaletteFocusSurface: View {
    let model: BrowserCommandPaletteModel
    let intent: DeferredPaletteFocus
    @State private var focused = false
    @State private var enabled = true

    var body: some View {
        BrowserCommandPaletteSearchField(model: model, presentation: .overlay, queryIsFocused: $focused)
            .disabled(!enabled)
            .onAppear {
                intent.request = { focused = true }
                intent.setEnabled = { enabled = $0 }
            }
    }
}
