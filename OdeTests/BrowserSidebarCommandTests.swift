import AppKit
import SwiftUI
import XCTest

@testable import Ode

/// Sidebar shortcuts act on their owning window, even after a utility is already open.
@MainActor
final class BrowserSidebarCommandTests: XCTestCase {
    // MARK: - Static Variables

    private static let utilityCommands: [(ShortcutCommand, BrowserUtilitySurface)] = [
        (.showHistory, .history), (.showArchive, .archive), (.showDownloads, .downloads),
    ]

    // MARK: - Actions - Sidebar routing

    /// Repeated commands in one turn must alternate their requested state,
    /// without a deferred dock replaying after the person hides the sidebar.
    func testRepeatedSidebarCommandsKeepTheLatestRequestInTheirOwningWindow() async {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let otherWindow = BrowserChromeState()
        for layout in BrowserTabLayout.all {
            for style in BrowserSidebarStyle.all {
                let chrome = BrowserChromeState(sidebarIsPresented: false)
                chrome.tabLayout = layout
                chrome.sidebarStyle = style
                let model = BrowserRootModel(
                    browser: browser, pages: pages, chrome: chrome,
                    spaceAccess: BrowserSpaceAccessController(), windowState: nil,
                    startupBehavior: .showStartPage, persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
                let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)

                actions.perform(.toggleSidebar)
                let pendingDock = model.sidebarMorphTask
                XCTAssertEqual(chrome.columnVisibility, .all)
                actions.perform(.toggleSidebar)
                XCTAssertEqual(chrome.columnVisibility, .detailOnly)
                await pendingDock?.value
                XCTAssertEqual(chrome.columnVisibility, .detailOnly)
                XCTAssertEqual(otherWindow.columnVisibility, .all)
            }
        }
    }

    /// A command can reverse a floating card's handoff while retaining it
    /// under the pointer; leaving afterwards still puts the card away.
    func testSidebarCommandsReversePointerHandoffWithoutReplayingAnOlderDock() async {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        for reduceMotion in [false, true] {
            let chrome = BrowserChromeState(sidebarIsPresented: false)
            let model = BrowserRootModel(
                browser: browser, pages: pages, chrome: chrome,
                spaceAccess: BrowserSpaceAccessController(), windowState: nil,
                startupBehavior: .showStartPage, persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
            model.revealFloatingSidebarFromPointer(reduceMotion: reduceMotion)
            model.sidebarSurfaceHoverChanged(true, reduceMotion: reduceMotion)
            if !reduceMotion { model.dockSidebar(reduceMotion: reduceMotion) }
            let pendingDock = model.sidebarMorphTask
            model.toggleSidebar(reduceMotion: reduceMotion)
            XCTAssertEqual(chrome.columnVisibility, .all)
            model.toggleSidebar(reduceMotion: reduceMotion)
            XCTAssertEqual(chrome.columnVisibility, .detailOnly)
            XCTAssertTrue(chrome.isFloatingSidebarPresented)
            await pendingDock?.value
            await model.sidebarMorphTask?.value
            XCTAssertEqual(chrome.columnVisibility, .detailOnly)
            XCTAssertTrue(chrome.isFloatingSidebarPresented)
            model.sidebarSurfaceHoverChanged(false, reduceMotion: reduceMotion)
            XCTAssertFalse(chrome.isFloatingSidebarPresented)
        }
    }

    /// Placement is idempotent from any layout and leaves browsing ownership
    /// and the person's sidebar size/style choices intact.
    func testDirectTabPlacementCommandsPersistTheirDestinationWithoutChangingTabs() {
        let defaults = BrowserChromeAppearancePreference.defaults
        let appearance = BrowserDeviceAppearanceStore.shared
        let previousSide = appearance.sidebarOnRight
        let previousBorderWidth = appearance.windowBorderWidth
        let keys = [
            BrowserChromeAppearancePreference.tabLayoutKey, BrowserChromeAppearancePreference.sidebarOnRightKey,
            BrowserChromeAppearancePreference.sidebarStyleKey, BrowserChromeAppearancePreference.borderWidthKey,
        ]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            appearance.sidebarOnRight = previousSide
            appearance.windowBorderWidth = previousBorderWidth
            appearance.saveNow()
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(BrowserSidebarStyle.icons.name, forKey: BrowserChromeAppearancePreference.sidebarStyleKey)
        appearance.windowBorderWidth = 3.5
        appearance.sidebarOnRight = false
        appearance.saveNow()
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        let space = browser.shownSpace?.id
        let tab = browser.shownTab?.id
        let cases: [(ShortcutCommand, BrowserTabLayout, Bool)] = [
            (.showTabsOnRight, .sidebar, true), (.showTabsOnTop, .top, true),
            (.showTabsOnLeft, .sidebar, false), (.showTabsOnTop, .top, false),
        ]
        for (command, layout, onRight) in cases {
            actions.perform(command)
            actions.perform(command)
            XCTAssertEqual(actions.tabLayout, layout)
            XCTAssertEqual(appearance.sidebarOnRight, onRight, "Placement must update the appearance windows observe.")
            appearance.saveNow()
            XCTAssertEqual(defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey), onRight)
            XCTAssertEqual(actions.sidebarStyle, .icons)
            XCTAssertEqual(defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), 3.5)
            XCTAssertEqual(browser.shownSpace?.id, space)
            XCTAssertEqual(browser.shownTab?.id, tab)
        }
        actions.perform(.showTabsOnLeft)
        for onRight in [true, false] {
            actions.perform(.toggleSidebarSide)
            XCTAssertEqual(appearance.sidebarOnRight, onRight)
            appearance.saveNow()
            XCTAssertEqual(defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey), onRight)
            XCTAssertEqual(actions.tabLayout, .sidebar)
        }
    }

    // MARK: - Actions - Search routing

    /// Mounted utility search takes keyboard input from an unrelated native responder in either sidebar mode.
    func testFindMovesNativeFocusIntoUtilitySearch() async throws {
        for sidebarIsPresented in [false, true] {
            try await verifyUtilitySearchFocus(sidebarIsPresented: sidebarIsPresented)
        }
    }

    /// Find issued before the field exists is delivered once, without stealing focus on a remount.
    func testFindBeforeUtilityMountIsConsumedWithoutReplayingOnRemount() async throws {
        try await verifyUtilitySearchFocus(sidebarIsPresented: true, requestsBeforeMount: true)
    }

    /// Authorization must still hold when a requested field becomes available, not only at command dispatch.
    func testPendingHistoryFindDoesNotFocusALockedSpace() async throws {
        try await verifyUtilitySearchFocus(sidebarIsPresented: true, requestsBeforeMount: true, locksBeforeMount: true)
    }

    /// Hiding the sidebar between command dispatch and mounting cancels input intended for History.
    func testPendingHistoryFindDoesNotFocusAHiddenSidebar() async throws {
        try await verifyUtilitySearchFocus(
            sidebarIsPresented: true, requestsBeforeMount: true, hidesBeforeMount: true)
    }

    /// A native responder outside the browser distinguishes requested focus from automatic window focus.
    private func verifyUtilitySearchFocus(
        command: ShortcutCommand = .showHistory, surface: BrowserUtilitySurface = .history,
        sidebarIsPresented: Bool, requestsBeforeMount: Bool = false,
        locksBeforeMount: Bool = false, hidesBeforeMount: Bool = false
    ) async throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let chrome = BrowserChromeState(sidebarIsPresented: sidebarIsPresented)
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        actions.perform(command)
        let frame = CGRect(x: 0, y: 0, width: 1120, height: 720)
        let container = NSView(frame: frame)
        let sentinel = NSTextField(string: "Outside browser")
        sentinel.frame = CGRect(x: 500, y: 20, width: 180, height: 24)
        container.addSubview(sentinel)
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer {
            window.close()
            pages.reconcile(validTabIDs: [])
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        XCTAssertTrue(window.makeFirstResponder(sentinel))
        XCTAssertTrue(actions.canPerform(.findInPage))
        if requestsBeforeMount { actions.perform(.findInPage) }
        if locksBeforeMount {
            let space = try XCTUnwrap(browser.shownSpace)
            browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        }
        if hidesBeforeMount {
            actions.perform(.toggleSidebar)
            XCTAssertNil(chrome.utilityPresentation.surface)
        }
        func makeHost() -> NSHostingView<BrowserRootView> {
            let host = NSHostingView(
                rootView: BrowserRootView(
                    browser: browser, pages: pages, chrome: chrome,
                    transientBrowsing: BrowserTransientBrowsingCoordinator(), persistSidebarWidth: { _ in }))
            host.frame = frame
            container.addSubview(host, positioned: .below, relativeTo: sentinel)
            host.layoutSubtreeIfNeeded()
            return host
        }
        let host = makeHost()
        if locksBeforeMount || hidesBeforeMount {
            try await Task.sleep(for: .milliseconds(250))
            let field = (window.firstResponder as? NSTextView)?.delegate as? NSTextField
            XCTAssertNotEqual(field?.placeholderString, String(localized: surface.searchPrompt))
            if locksBeforeMount {
                XCTAssertTrue(field === sentinel)
                XCTAssertFalse(actions.canPerform(.findInPage))
            }
            if hidesBeforeMount {
                actions.perform(command)
                actions.perform(.findInPage)
                _ = try await utilitySearchEditor(for: surface, in: host, window: window)
            }
            return
        }
        if !requestsBeforeMount {
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(window.makeFirstResponder(sentinel))
            actions.perform(.findInPage)
        }
        let editor = try await utilitySearchEditor(for: surface, in: host, window: window)
        editor.insertText("utility-route", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.string, "utility-route")
        guard requestsBeforeMount else { return }
        host.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.makeFirstResponder(sentinel))
        let beforeRemount = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertTrue(
            beforeRemount.delegate as? NSTextField === sentinel, "The remount starts with external input focused.")
        let replacement = makeHost()
        try await Task.sleep(for: .milliseconds(250))
        let remountedField = (window.firstResponder as? NSTextView)?.delegate as? NSTextField
        // A new browser root may focus its start-page input; it must not replay focus into utility search.
        XCTAssertNotEqual(
            remountedField?.placeholderString, String(localized: surface.searchPrompt),
            "Remounting must not replay a consumed Find.")
        actions.perform(.findInPage)
        _ = try await utilitySearchEditor(for: surface, in: replacement, window: window)
    }

    /// Waits for the actual utility input control rather than inspecting a focus-request counter.
    private func utilitySearchEditor(for surface: BrowserUtilitySurface, in host: NSView, window: NSWindow) async throws
        -> NSTextView
    {
        for _ in 0..<20 {
            if let editor = window.firstResponder as? NSTextView,
                let field = editor.delegate as? NSTextField, field.isDescendant(of: host),
                field.placeholderString == String(localized: surface.searchPrompt)
            {
                return editor
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(nil as NSTextView?, "Find must focus the selected utility search field.")
    }

    /// Ordinary browsing and a dismissed utility retain page Find.
    func testFindUsesTheLoadedPageWhenNoUtilityIsVisible() async throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let tab = TabState.Seed(title: "Find page", url: url, placement: .current)
        let space = SpaceState.Seed(name: "Page find", symbol: "globe", accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        for _ in 0..<40 {
            if page.live.documentURL != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(page.live.documentURL)
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        XCTAssertTrue(actions.canPerform(.findInPage))
        actions.perform(.findInPage)
        XCTAssertTrue(page.isFindPresented)
        actions.perform(.showArchive)
        actions.perform(.showArchive)
        XCTAssertNil(chrome.utilityPresentation.surface)
        let previousRequest = page.findFocusRequest
        actions.perform(.findInPage)
        XCTAssertGreaterThan(page.findFocusRequest, previousRequest)
    }

    /// Utility toggles preserve the docked preference and cannot close another window's History.
    func testRepeatingEachUtilityCommandClosesOnlyItsOwningWindowPanel() {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let otherWindow = BrowserChromeState()
        otherWindow.presentUtility(.history)
        for sidebarIsPresented in [false, true] {
            for (command, surface) in Self.utilityCommands {
                let chrome = BrowserChromeState(sidebarIsPresented: sidebarIsPresented)
                let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
                actions.perform(command)
                XCTAssertEqual(chrome.utilityPresentation.surface, surface)
                XCTAssertEqual(chrome.columnVisibility, sidebarIsPresented ? .all : .detailOnly)
                XCTAssertEqual(chrome.isFloatingSidebarPresented, !sidebarIsPresented)
                actions.perform(command)
                XCTAssertNil(chrome.utilityPresentation.surface)
                XCTAssertFalse(chrome.isFloatingSidebarPresented)
                XCTAssertEqual(chrome.columnVisibility, sidebarIsPresented ? .all : .detailOnly)
                XCTAssertEqual(otherWindow.utilityPresentation.surface, .history)
                actions.perform(command)
                XCTAssertEqual(chrome.utilityPresentation.surface, surface)
                XCTAssertEqual(chrome.isFloatingSidebarPresented, !sidebarIsPresented)
            }
        }
    }

    /// Hidden and protected utility panels must not expose their search commands.
    func testFindDoesNotSearchAHiddenOrLockedUtilityList() throws {
        for (command, _) in Self.utilityCommands {
            let browser = BrowserStore.hostingPages()
            let chrome = BrowserChromeState()
            let actions = BrowserCommandActions(
                browser: browser, pages: BrowserPagePool(browser: browser), chrome: chrome, windows: nil)
            actions.perform(command)
            chrome.hideSidebar()
            XCTAssertFalse(actions.canPerform(.findInPage))
            actions.perform(command)
            XCTAssertTrue(actions.canPerform(.findInPage))
            let space = try XCTUnwrap(browser.shownSpace)
            browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
            XCTAssertFalse(actions.canPerform(.findInPage))
        }
    }
}
