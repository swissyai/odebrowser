import AppKit
import XCTest

@testable import Ode

/// A test run keeps its windows away from the person: whatever a test does
/// to show, move or center a window, it stays off every screen, the host
/// never comes forward, and the person's pointer reaches no test.
@MainActor
final class BrowserTestHostWindowTests: XCTestCase {
    func testAWindowATestShowsMovesOrCentersStaysOffEveryScreen() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func isOnAScreen() -> Bool { NSScreen.screens.contains { $0.frame.intersects(window.frame) } }

        window.makeKeyAndOrderFront(nil)
        XCTAssertFalse(isOnAScreen())
        window.center()
        XCTAssertFalse(isOnAScreen())
        window.setFrameOrigin(NSPoint(x: 200, y: 200))
        XCTAssertFalse(isOnAScreen())
        window.setFrameTopLeftPoint(NSPoint(x: 200, y: 600))
        XCTAssertFalse(isOnAScreen())
        window.setFrame(NSRect(x: 10, y: 10, width: 500, height: 400), display: false)
        XCTAssertFalse(isOnAScreen())
        window.setFrame(NSRect(x: 20, y: 20, width: 500, height: 400), display: false, animate: false)
        XCTAssertFalse(isOnAScreen())
        window.alphaValue = 0
        window.alphaValue = 1
        XCTAssertFalse(isOnAScreen())
        XCTAssertEqual(window.frame.size, NSSize(width: 500, height: 400), "A window keeps the size it was given.")
    }

    func testAnAttachedPanelAndItsParentStayOffEveryScreenDuringSheetLayout() {
        let parent = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        let panel = NSPanel(
            contentRect: NSRect(x: 160, y: 160, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
            defer: false)
        parent.isReleasedWhenClosed = false
        panel.isReleasedWhenClosed = false
        defer {
            parent.endSheet(panel)
            panel.close()
            parent.close()
        }

        parent.orderFront(nil)
        parent.beginSheet(panel)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        for window in [parent, panel] {
            XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
            window.center()
            window.setFrameTopLeftPoint(NSPoint(x: 200, y: 600))
            window.setFrame(NSRect(x: 10, y: 10, width: 500, height: 300), display: false, animate: false)
            XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
        }
        XCTAssertEqual(panel.sheetParent, parent)
        XCTAssertFalse(NSApp.isActive)
    }

    func testTheShiftedHostExcludesWindowsFromMissionControlWithoutMaskingCyclingBehavior() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.orderFront(nil)
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertFalse(window.collectionBehavior.contains(.ignoresCycle))

        // Later native configuration cannot put an offscreen window back in
        // Mission Control, but cycling and unrelated Space flags still apply.
        for management: NSWindow.CollectionBehavior in [.managed, .stationary] {
            window.collectionBehavior = [management, .participatesInCycle, .moveToActiveSpace, .fullScreenPrimary]
            XCTAssertEqual(
                window.collectionBehavior, [.transient, .participatesInCycle, .moveToActiveSpace, .fullScreenPrimary])
        }
        window.collectionBehavior = [.managed, .ignoresCycle]
        XCTAssertEqual(window.collectionBehavior, [.transient, .ignoresCycle])
    }

    func testTheHostNeverComesForwardAndThePointerStaysOutsideEveryWindow() {
        NSApp.activate()
        XCTAssertFalse(NSApp.isActive)
        XCTAssertEqual(BrowserPointerLocation.current(), BrowserPointerLocation.outsideEveryWindow)
    }
}
