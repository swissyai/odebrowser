import AppKit
import XCTest

@testable import Ode

@MainActor
final class BrowserGettingStartedTourTests: XCTestCase {
    // MARK: - Actions - Ownership and persistence

    func testOnlyFreshSetupCanStartAutomaticallyAndReplayStaysExplicit() throws {
        let suite = "GettingStartedTourTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = BrowserStore(seed: .preview)
        let chrome = BrowserChromeState()
        let guide = try openGuide(in: browser)
        let tour = BrowserGettingStartedTour(defaults: defaults, browser: browser, chrome: chrome)
        XCTAssertFalse(tour.isRunning, "A launch or a saved guide must not start the tour")
        tour.start(guide, automatically: true)
        XCTAssertTrue(tour.isShowingGuide)
        tour.finishBrowsing(completed: false)
        XCTAssertNotEqual(browser.shownTab?.id, guide.tabID)
        XCTAssertNotNil(browser.shownSpace?.tabs.model(guide.tabID))
        browser.selectTab(guide.tabID)
        let relaunched = BrowserGettingStartedTour(defaults: defaults, browser: browser, chrome: chrome)
        XCTAssertEqual(relaunched.disposition, .dismissed)
        relaunched.start(guide, automatically: true)
        XCTAssertFalse(relaunched.isRunning)
        relaunched.replay()
        XCTAssertTrue(relaunched.isShowingGuide)
        relaunched.dismiss(completed: true)
        XCTAssertEqual(
            BrowserGettingStartedTour(defaults: defaults, browser: browser, chrome: chrome).disposition, .completed)
        XCTAssertNotNil(browser.shownSpace?.tabs.model(guide.tabID), "The saved guide remains replayable")
    }

    func testAStaleProfileAndAChangedSelectionCannotDriveTourProgress() throws {
        let browser = BrowserStore(seed: .preview)
        let chrome = BrowserChromeState()
        let guide = try openGuide(in: browser)
        let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
        tour.start(
            BrowserTabRuntimeAssignment(tabID: guide.tabID, spaceID: guide.spaceID, profileID: UUID()),
            automatically: true)
        XCTAssertFalse(tour.isRunning)
        tour.start(guide, automatically: true)
        browser.openNewTab()
        tour.commandBarOpened()
        tour.copiedCard(.calculation)
        XCTAssertFalse(tour.confirmed)
        tour.clearConfirmation()
        XCTAssertEqual(tour.step, .commandBar)
        XCTAssertFalse(tour.isShowingGuide)
        XCTAssertFalse(tour.handleCancel(try escape()))
        chrome.presentCommandPalette()
        let unrelatedTabID = browser.shownTab?.id
        tour.finishBrowsing(completed: false)
        XCTAssertTrue(chrome.isCommandPalettePresented, "A stale guide cannot close another tab's palette")
        XCTAssertEqual(browser.shownTab?.id, unrelatedTabID)
        XCTAssertFalse(tour.isRunning)
    }

    func testOnlyActualOutcomesAdvanceAndAnUnfinishedSidebarExerciseRestoresItsOriginalState() throws {
        let browser = BrowserStore(seed: .preview)
        let chrome = BrowserChromeState()
        chrome.sidebarToggle = { [weak chrome] in
            guard let chrome else { return }
            chrome.columnVisibility = chrome.columnVisibility == .detailOnly ? .all : .detailOnly
        }
        let guide = try openGuide(in: browser)
        let original = browser.sessionSeed
        let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
        chrome.gettingStartedTour = tour
        tour.start(guide, automatically: false)
        XCTAssertEqual(tour.step, .commandBar)
        chrome.presentCommandPalette()
        XCTAssertTrue(tour.confirmed)
        XCTAssertEqual(tour.step, .answer)
        tour.copiedCard(.translation)
        XCTAssertEqual(tour.confirmation, .commandBar)
        tour.copiedCard(.calculation)
        XCTAssertTrue(tour.confirmed)
        XCTAssertEqual(tour.confirmation, .answer)
        XCTAssertEqual(tour.step, .sidebar)
        tour.clearConfirmation()
        XCTAssertFalse(chrome.isCommandPalettePresented)
        chrome.columnVisibility = .detailOnly
        XCTAssertEqual(tour.step, .sidebar, "The return press is part of the exercise")
        XCTAssertEqual(tour.confirmation, .sidebar)
        tour.dismiss()
        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(browser.sessionSeed, original)
    }

    func testPrivateWindowsCannotStartOrPersistATour() throws {
        let suite = "GettingStartedTourPrivateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = BrowserStore(seed: .preview, browsingMode: .privateBrowsing)
        let chrome = BrowserChromeState()
        let guide = try openGuide(in: browser)
        let tour = BrowserGettingStartedTour(defaults: defaults, browser: browser, chrome: chrome)
        tour.start(guide, automatically: true)
        tour.replay()
        tour.dismiss()
        XCTAssertFalse(tour.isRunning)
        XCTAssertNil(defaults.string(forKey: BrowserGettingStartedTour.defaultsKey))
    }

    func testRapidOutcomesDoNotWaitForFeedbackAndFinishKeepsTheSavedGuide() throws {
        for completed in [true, false] {
            let browser = BrowserStore(seed: .preview)
            let chrome = BrowserChromeState()
            let fallbackID = try XCTUnwrap(browser.shownTab?.id)
            let guide = try openGuide(in: browser)
            let original = browser.sessionSeed
            let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
            chrome.gettingStartedTour = tour
            tour.start(guide, automatically: false)
            chrome.presentCommandPalette()
            tour.copiedCard(.calculation)
            XCTAssertFalse(chrome.isCommandPalettePresented)
            // A reopened palette belongs to the person, not delayed tour feedback.
            chrome.presentCommandPalette()
            tour.clearConfirmation()
            XCTAssertTrue(chrome.isCommandPalettePresented)
            chrome.hideSidebar()
            chrome.showSidebar()
            XCTAssertEqual(tour.step, .finished)
            XCTAssertEqual(chrome.columnVisibility, .all)
            tour.finishBrowsing(completed: completed)
            XCTAssertFalse(
                chrome.isCommandPalettePresented, "Returning to browsing closes the matching guide’s palette")
            XCTAssertEqual(tour.disposition, completed ? .completed : .dismissed)
            XCTAssertFalse(tour.isRunning)
            XCTAssertEqual(browser.shownTab?.id, fallbackID)
            let after = browser.sessionSeed
            var expected = original
            let spaceIndex = try XCTUnwrap(expected.spaces.firstIndex { $0.id == guide.spaceID })
            let tabIndex = try XCTUnwrap(expected.spaces[spaceIndex].tabs.firstIndex { $0.id == fallbackID })
            let activation = after.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt
            XCTAssertGreaterThanOrEqual(activation, expected.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt)
            // Returning through the normal dismissal route records only that tab's use.
            expected.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = activation
            XCTAssertEqual(after, expected)
        }
    }

    func testNativeEscapeYieldsToThePaletteAndDismissesOnlyTheMatchingGuide() throws {
        let browser = BrowserStore(seed: .preview)
        let chrome = BrowserChromeState()
        chrome.sidebarToggle = { [weak chrome] in
            guard let chrome else { return }
            chrome.columnVisibility = chrome.columnVisibility == .detailOnly ? .all : .detailOnly
        }
        let guide = try openGuide(in: browser)
        let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
        chrome.gettingStartedTour = tour
        tour.start(guide, automatically: false)
        XCTAssertFalse(tour.handleCancel(try escape(modifiers: .option)))
        XCTAssertFalse(tour.handleCancel(try escape(type: .keyUp)))
        XCTAssertTrue(tour.handleCancel(try escape()))
        XCTAssertEqual(tour.disposition, .dismissed)
        XCTAssertNotEqual(browser.shownTab?.id, guide.tabID)
        XCTAssertNotNil(browser.shownSpace?.tabs.model(guide.tabID))

        browser.selectTab(guide.tabID)
        tour.replay()
        chrome.presentCommandPalette()
        XCTAssertFalse(tour.handleCancel(try escape()), "The palette receives the first Escape")
        XCTAssertTrue(tour.isRunning)
        tour.copiedCard(.calculation)
        tour.clearConfirmation()
        chrome.hideSidebar()
        XCTAssertTrue(tour.handleCancel(try escape()))
        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertFalse(tour.isRunning)
        XCTAssertNotEqual(browser.shownTab?.id, guide.tabID)
        XCTAssertEqual(browser.shownSpace?.tabs.model(guide.tabID)?.placement, .saved)
    }

    func testExpectedKeysTrackDownAndUpAndDoNotRetainUnrelatedInput() throws {
        let browser = BrowserStore(seed: .preview)
        _ = BrowserShortcutStore(core: browser.core)
        let chrome = BrowserChromeState()
        let guide = try openGuide(in: browser)
        let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
        chrome.gettingStartedTour = tour
        tour.start(guide, automatically: false)
        let commandT = try key(code: 17, characters: "t", modifiers: .command)
        tour.updateKeyState(try key(code: 0, characters: "a", modifiers: .command))
        XCTAssertNil(tour.heldShortcut)
        tour.updateKeyState(commandT)
        XCTAssertEqual(tour.heldShortcut, tour.expectedShortcut)
        XCTAssertEqual(tour.pressedKeys(for: try XCTUnwrap(tour.heldShortcut)), [0, 1])
        chrome.presentCommandPalette()
        tour.updateKeyState(try key(code: 17, characters: "t", modifiers: .command, type: .keyUp))
        XCTAssertNil(tour.heldShortcut)
        XCTAssertEqual(tour.confirmation, .commandBar, "Completion stays after the chord is released")
        tour.offerAnswer({ true }, hasNumericAnswer: true)
        let tab = try XCTUnwrap(tour.expectedShortcut)
        XCTAssertFalse(tab.isValid, "The visualization must not make Tab an assignable global shortcut")
        tour.updateKeyState(try key(code: 48, characters: "\t"))
        XCTAssertEqual(tour.heldShortcut, tab)
        XCTAssertEqual(tour.pressedKeys(for: tab), [0])
        tour.updateKeyState(try key(code: 48, characters: "\t", type: .keyUp))
        XCTAssertNil(tour.heldShortcut)
        tour.updateKeyState(try key(code: 48, characters: "\t", repeatKey: true))
        XCTAssertNil(tour.heldShortcut)
        tour.updateKeyState(try key(code: 48, characters: "\t"))
        tour.resetPressedKeys()
        XCTAssertNil(tour.heldShortcut)
        XCTAssertTrue(tour.pressedModifiers.isEmpty)
        tour.dismiss()
        tour.updateKeyState(commandT)
        XCTAssertNil(tour.heldShortcut)
    }

    func testReleasingAChordModifierWithoutKeyUpAllowsTheNextExpectedKey() throws {
        for eventType in [NSEvent.EventType.flagsChanged, .keyDown] {
            let browser = BrowserStore(seed: .preview)
            _ = BrowserShortcutStore(core: browser.core)
            let chrome = BrowserChromeState()
            let tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: chrome)
            chrome.gettingStartedTour = tour
            tour.start(try openGuide(in: browser), automatically: false)
            tour.updateKeyState(try key(code: 17, characters: "t", modifiers: .command))
            chrome.presentCommandPalette()
            let commandT = try XCTUnwrap(tour.heldShortcut)
            tour.updateKeyState(try key(code: 56, characters: "", modifiers: [.command, .shift], type: .flagsChanged))
            XCTAssertEqual(tour.heldShortcut, commandT, "Adding a modifier does not release the original chord")

            // A command's key-up need not arrive before its modifier is
            // released. Later native input is authoritative about modifiers.
            tour.updateKeyState(
                try key(code: eventType == .flagsChanged ? 55 : 18, characters: "", type: eventType))
            XCTAssertNil(tour.heldShortcut, "A chord cannot remain held after its required modifier is released")
            XCTAssertEqual(tour.confirmation, .commandBar, "Releasing keys does not undo the real outcome")
            tour.offerAnswer({ true }, hasNumericAnswer: true)
            let tab = try XCTUnwrap(tour.expectedShortcut)
            tour.updateKeyState(try key(code: 48, characters: "\t"))
            XCTAssertEqual(tour.heldShortcut, tab, "A stale opening chord must not block the next expected input")
            XCTAssertEqual(tour.pressedKeys(for: tab), [0])
            tour.updateKeyState(try key(code: 48, characters: "\t", type: .keyUp))
            XCTAssertNil(tour.heldShortcut)
            XCTAssertTrue(tour.pressedKeys(for: tab).isEmpty)
        }
    }

    private func key(
        code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = [],
        type: NSEvent.EventType = .keyDown, repeatKey: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code))
    }

    // MARK: - Actions - Fixtures

    private func escape(
        modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
    }

    private func openGuide(in browser: BrowserStore) throws -> BrowserTabRuntimeAssignment {
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.shownSpace)
        return BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
    }
}
