import AppKit
import XCTest

@testable import Ode

/// Every command the core names runs in the Mac shell, and every way the
/// core says a palette row activates has a way to run it. A kind left out
/// would quietly never be offered or never run.
@MainActor
final class BrowserCommandCoverageTests: XCTestCase {
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
