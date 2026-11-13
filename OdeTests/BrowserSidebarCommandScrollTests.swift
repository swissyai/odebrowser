import AppKit
import SwiftUI
import XCTest

@testable import Ode

/// Wheel-only routing must leave the Command Bar's native text input alone.
@MainActor
final class BrowserSidebarCommandScrollTests: XCTestCase {
    func testNativeSidebarWheelPreservesResponderSelectionAndMarkedText() async throws {
        let (window, host, browser, pages, chrome) = makeBrowserFixture()
        defer {
            window.close()
            pages.reconcile(validTabIDs: [])
        }
        try await Task.sleep(for: .milliseconds(150))
        chrome.presentCommandPalette()
        for _ in 0..<20 {
            if let editor = window.firstResponder as? NSTextView,
                let field = editor.delegate as? NSTextField,
                field.accessibilityIdentifier() == BrowserCommandPalettePresentation.overlay.fieldIdentifier
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        let routing = try XCTUnwrap(find(BrowserSidebarCommandScrollBridge.RoutingView.self, in: host).first)
        let sidebar = routing.convert(routing.bounds, to: nil)
        let scroll = try XCTUnwrap(
            find(NSScrollView.self, in: host).first { scroll in
                let frame = scroll.convert(scroll.bounds, to: nil)
                return frame.intersects(sidebar) && frame.width <= sidebar.width
                    && (scroll.documentView?.frame.height ?? 0) > scroll.contentSize.height
            })
        let frame = scroll.convert(scroll.bounds, to: nil)
        let point = NSPoint(x: frame.minX + 40, y: frame.midY)
        editor.insertText(
            "typed command query", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.setSelectedRange(NSRange(location: 2, length: 5))
        let selection = editor.selectedRange()
        let text = editor.string
        let selectedTab = browser.shownTab?.id
        let selectedSpace = browser.shownSpace?.id
        let before = scroll.contentView.bounds.origin

        try await wheel(routing, in: window, at: point)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNotEqual(scroll.contentView.bounds.origin, before)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string, text)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertTrue(chrome.isCommandPalettePresented)
        XCTAssertEqual(browser.shownTab?.id, selectedTab)
        XCTAssertEqual(browser.shownSpace?.id, selectedSpace)

        editor.setMarkedText("compose", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
        let marked = editor.markedRange()
        let composingText = editor.string
        try await wheel(routing, in: window, at: point)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string, composingText)
        XCTAssertEqual(editor.markedRange(), marked)
        XCTAssertTrue(editor.hasMarkedText())
    }

    func testWheelDoesNotRouteThroughTheCardOrIntoHiddenAndOtherWindows() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let event = try scrollEvent(.changed, delta: -60)
        let boundary = BrowserPlatformCommandPaletteScrollBoundary.BoundaryView(
            frame: NSRect(x: 50, y: 200, width: 100, height: 150))
        fixture.window.contentView?.addSubview(boundary)
        let point = NSPoint(x: 100, y: 300)
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: point))
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: NSPoint(x: 300, y: 100)))
        let other = NSWindow()
        other.isReleasedWhenClosed = false
        defer { other.close() }
        XCTAssertFalse(fixture.routing.routeWheel(event, in: other, at: point))
        boundary.removeFromSuperview()
        let pageOrigin = fixture.page.contentView.bounds.origin
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: NSPoint(x: 100, y: 350)))
        XCTAssertEqual(fixture.page.contentView.bounds.origin, pageOrigin)
        fixture.routing.isHidden = true
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: point))
        fixture.routing.isHidden = false
        fixture.routing.setRoutingEnabled(false)
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: point))
        fixture.routing.setRoutingEnabled(true)
        fixture.routing.removeFromSuperview()
        XCTAssertFalse(fixture.routing.routeWheel(event, in: fixture.window, at: point))
    }

    private func find<NativeView: NSView>(_ type: NativeView.Type, in view: NSView) -> [NativeView] {
        (view as? NativeView).map { [$0] } ?? view.subviews.flatMap { find(type, in: $0) }
    }

    private func makeBrowserFixture() -> (
        NSWindow, NSView, BrowserStore, BrowserPagePool, BrowserChromeState
    ) {
        let tabs = (0..<40).map { index in
            TabState.Seed(title: "Tab \(index)", url: URL(string: "about:blank#\(index)"), placement: .current)
        }
        let space = SpaceState.Seed(name: "Wheel", symbol: "globe", accent: .indigo, folders: [], tabs: tabs)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tabs[0].id])
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        let chrome = BrowserChromeState()
        let host = NSHostingView(
            rootView: BrowserRootView(
                browser: browser, pages: pages, chrome: chrome,
                transientBrowsing: BrowserTransientBrowsingCoordinator(), persistSidebarWidth: { _ in }))
        let window = SidebarWheelWindow(
            contentRect: NSRect(x: -40000, y: -40000, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        return (window, host, browser, pages, chrome)
    }

    private func makeFixture() -> (
        window: NSWindow, field: NSTextField, scroll: NSScrollView,
        routing: BrowserSidebarCommandScrollBridge.RoutingView, page: NSScrollView
    ) {
        let window = SidebarWheelWindow(
            contentRect: NSRect(x: -40000, y: -40000, width: 500, height: 400),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        window.contentView = content
        let page = NSScrollView(frame: content.bounds)
        page.documentView = SidebarWheelDocument(frame: NSRect(x: 0, y: 0, width: 500, height: 2400))
        content.addSubview(page)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        scroll.hasVerticalScroller = true
        scroll.documentView = SidebarWheelDocument(frame: NSRect(x: 0, y: 0, width: 200, height: 2400))
        scroll.documentView?.addSubview(BrowserSidebarCommandScrollBridge.DocumentView(frame: .zero))
        content.addSubview(scroll)
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 220, y: 340, width: 250, height: 30)
        content.addSubview(field)
        let routing = BrowserSidebarCommandScrollBridge.RoutingView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        content.addSubview(routing)
        window.orderFront(nil)
        window.makeFirstResponder(field)
        routing.setRoutingEnabled(true)
        return (window, field, scroll, routing, page)
    }

    private func wheel(
        _ routing: BrowserSidebarCommandScrollBridge.RoutingView, in window: NSWindow, at point: NSPoint
    ) async throws {
        for (phase, delta): (CGScrollPhase, Int32) in [(.began, -1), (.changed, -89), (.ended, 0)] {
            let event = try scrollEvent(phase, delta: delta)
            NSApplication.shared.postEvent(event, atStart: true)
            let queued = try XCTUnwrap(
                NSApplication.shared.nextEvent(
                    matching: .scrollWheel, until: .distantPast, inMode: .default, dequeue: true))
            XCTAssertTrue(routing.routeWheel(queued, in: window, at: point))
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Construct an in-process native event; never post input to the desktop.
    private func scrollEvent(_ phase: CGScrollPhase, delta: Int32) throws -> NSEvent {
        let event = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.timestamp = DispatchTime.now().uptimeNanoseconds
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}

private final class SidebarWheelWindow: NSWindow {
    override var screen: NSScreen? { NSScreen.screens.first }
}

private final class SidebarWheelDocument: NSView {
    override var isFlipped: Bool { true }
}
