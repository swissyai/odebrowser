import AppKit
import Observation
import XCTest

@testable import Ode

@MainActor
final class BrowserTabMultiSelectionTests: XCTestCase {
    func testBatchDismissalDefersAllChangesAndRevalidatesAfterNativeConfirmation() throws {
        final class DeferredDismissal: BrowserPageDismissalAuthorizing {
            var assignments: [BrowserTabRuntimeAssignment] = []
            var operation: (@MainActor () -> Bool)?
            func performDismissal(
                of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
                operation: @escaping @MainActor () -> Bool
            ) -> Bool {
                self.assignments = assignments
                self.operation = operation
                return false
            }
        }
        let session = makeSession(count: 3)
        let source = session.spaces[0]
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let gate = DeferredDismissal()
        browser.family.pageDismissalAuthorizer = gate
        let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
        let request = try XCTUnwrap(browser.capturedSelection(ids: Array(source.tabs.prefix(2).map(\.id))))
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertEqual(gate.assignments.map(\.tabID), request.ids)
        XCTAssertEqual(browser.sessionSeed, opened)
        gate.operation = nil  // Native cancellation never commits a subset.
        XCTAssertEqual(browser.sessionSeed, opened)
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertTrue(browser.moveTab(source.tabs[0].id, to: .saved))
        let changed = browser.sessionSeed
        XCTAssertFalse(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.sessionSeed, changed)
        XCTAssertTrue(browser.moveTab(source.tabs[0].id, to: .current, before: source.tabs[1].id))
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertTrue(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.spaceModels[0].archive.entries.count, 2)
        XCTAssertEqual(browser.spaceModels[0].tabs.models.map(\.id), [source.tabs[2].id])
    }

    func testDragCarriesCapturedBatchAndCancellationRestoresEveryLiftedRow() throws {
        let session = makeSession(count: 3)
        let source = session.spaces[0]
        let ids = [source.tabs[0].id, source.tabs[2].id]
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let request = try XCTUnwrap(browser.capturedSelection(ids: ids))
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: ids[0], spaceID: source.id, profileID: source.profileID)
        ).selecting(request)
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let state = sidebarInteraction.sidebarReorderState
        state.begin(item: item, section: .tabs(placement: .current, folderID: nil), at: .zero)
        XCTAssertTrue(state.isLifted(.tab(ids[0])))
        XCTAssertTrue(state.isLifted(.tab(ids[1])))
        state.cancel()
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.isLifted(.tab(ids[1])))
        XCTAssertEqual(browser.sessionSeed, opened)
        let forbidden = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0))
        // The core refuses pinning more than one tab, and the window says why.
        XCTAssertFalse(browser.sidebarDrop(item, on: forbidden.kind))
        XCTAssertEqual(
            browser.tabMultiSelection.message, Rejection.pinsOneTabAtATime(PinsOneTabAtATime()).placementExplanation)
        XCTAssertEqual(browser.sessionSeed, opened)
        let target = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .saved, folderID: nil), beforeID: nil, index: 0))
        browser.tabMultiSelection.selectAll(units: [[source.tabs[1].id]])
        XCTAssertTrue(browser.sidebarDrop(item, on: target.kind))
        XCTAssertEqual(browser.shownSpace?.savedTabs.map(\.id), ids)
        XCTAssertEqual(browser.shownSpace?.currentTabs.map(\.id), [source.tabs[1].id])
    }

    func testSelectedAncestorCarriesDescendantsOnlyOnceAndEmptyFoldersRemainMovable() throws {
        var session = makeSession(count: 1)
        let parent = UUID()
        let child = UUID()
        session.spaces[0].folders = [
            FolderState.Seed(id: parent, title: "Parent"),
            FolderState.Seed(id: child, title: "Empty child", parentID: parent),
        ]
        let browser = makeBatchStore(session)
        let request = try XCTUnwrap(browser.capturedSelection([.folder(parent), .folder(child)]))
        XCTAssertEqual(request.rootItems, [.folder(parent)])
        XCTAssertTrue(request.ids.isEmpty)
        try browser.send(browser.filing(request, .current), for: request)
        session = browser.sessionSeed
        XCTAssertEqual(session.spaces[0].folders.first { $0.id == child }?.parentID, parent)
        XCTAssertTrue(session.spaces[0].folders.allSatisfy { $0.location == .current })
    }

    func testFolderAndWholeSplitCanBeWrappedWithoutFlatteningAndPinsAreExcluded() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        var created: UUID?
        session = try organized(session) { browser, space in
            created = browser.addFolder(title: "Empty", in: space.id)
            XCTAssertTrue(
                browser.addTabToSplit(
                    BrowserTabDragItem(tabID: ids[0], spaceID: space.id, profileID: space.profileID), joining: ids[1],
                    at: nil))
            XCTAssertTrue(browser.moveTab(ids[3], to: .pinned))
        }
        let folder = try XCTUnwrap(created)
        let items: [BrowserSelectionItemID] = [.folder(folder), .tab(ids[0]), .tab(ids[1]), .tab(ids[3])]
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: items.map { [$0] })
        let browser = makeBatchStore(session)
        let captured = try XCTUnwrap(browser.capturedSelection(items))
        let request = try XCTUnwrap(
            browser.capturedSelection(try XCTUnwrap(selection.releasePinnedTabs(from: captured))))
        XCTAssertFalse(request.ids.contains(ids[3]))
        XCTAssertTrue(selection.contains(.folder(folder)))
        try browser.send(browser.filingInNewFolder(request, in: .saved), for: request)
        session = browser.sessionSeed
        let result = session.spaces[0]
        let wrapper = try XCTUnwrap(result.folders.first { $0.id == folder }?.parentID)
        XCTAssertEqual(result.tabs.first { $0.id == ids[0] }?.folderID, wrapper)
        XCTAssertEqual(result.tabs.first { $0.id == ids[1] }?.folderID, wrapper)
        XCTAssertEqual(
            result.tabs.first { $0.id == ids[0] }?.splitGroupID, result.tabs.first { $0.id == ids[1] }?.splitGroupID)
        XCTAssertEqual(result.pinnedTabs.map(\.id), [ids[3]])
    }

    func testLogicalSelectionDoesNotExposeALockedSpaceWithoutLiveAuthorization() throws {
        var session = makeSession(count: 2)
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser), [])
        let access = BrowserSpaceAccessController()
        interaction.sidebarSpaceAccess = access
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser), [])
    }

    /// The sidebar's keys move, extend, clear and act on the selection, and
    /// only while its selection view holds the window's keyboard focus.
    func testSidebarKeysMoveExtendClearAndActOnTheSelection() throws {
        let browser = makeBatchStore(makeSession(count: 4))
        let space = try XCTUnwrap(browser.shownSpace)
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let access = BrowserSpaceAccessController()
        let units = BrowserSidebarSelection.itemUnits(in: browser)
        XCTAssertEqual(units.count, 4)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = BrowserTabSelectionMonitor.SelectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        var activated: [UUID] = []
        view.browser = browser
        view.sidebarInteraction = interaction
        view.spaceAccess = access
        view.assignment = BrowserSpaceRuntimeAssignment(space: space)
        view.activate = { activated.append($0) }
        window.contentView?.addSubview(view)
        defer {
            view.stop()
            window.close()
        }
        let selection = browser.tabMultiSelection
        func consumes(
            _ code: BrowserShortcutHardwareKeyCode?, _ characters: String = "", _ flags: NSEvent.ModifierFlags = []
        ) throws -> Bool {
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code?.rawValue ?? 7))
            return view.handle(event) == nil
        }
        func selected(_ indices: Int...) -> Set<BrowserSelectionItemID> { Set(indices.flatMap { units[$0] }) }

        XCTAssertFalse(try consumes(.downArrow))
        XCTAssertEqual(selection.selectedItems, [])
        window.makeFirstResponder(view)
        XCTAssertTrue(try consumes(.downArrow))
        XCTAssertEqual(selection.selectedItems, selected(1))
        XCTAssertTrue(try consumes(.downArrow, "", .shift))
        XCTAssertEqual(selection.selectedItems, selected(1, 2))
        XCTAssertEqual(selection.focusedItem, units[2][0])
        XCTAssertTrue(try consumes(.upArrow, "", .command))
        XCTAssertEqual(selection.selectedItems, selected(0))
        XCTAssertTrue(try consumes(.end))
        XCTAssertEqual(selection.selectedItems, selected(3))
        XCTAssertTrue(try consumes(.home))
        XCTAssertEqual(selection.selectedItems, selected(0))
        XCTAssertTrue(try consumes(nil, "a", .command))
        XCTAssertEqual(selection.selectedItems, selected(0, 1, 2, 3))
        XCTAssertTrue(try consumes(nil, "a", [.command, .shift]))
        XCTAssertEqual(selection.selectedItems, [])
        // With no anchor, a shift move ranges from the active tab.
        XCTAssertTrue(try consumes(.downArrow, "", .shift))
        XCTAssertEqual(selection.selectedItems, selected(0, 1))
        XCTAssertTrue(try consumes(.escape))
        XCTAssertEqual(selection.selectedItems, [])
        XCTAssertNil(selection.focusedItem)
        XCTAssertTrue(try consumes(.end))
        XCTAssertTrue(try consumes(.returnKey))
        XCTAssertEqual(activated, [try XCTUnwrap(units[3][0].tabID)])
        XCTAssertTrue(try consumes(nil, "d", .command))
        XCTAssertEqual(browser.shownSpace?.tabs.models.count, 5)
        XCTAssertFalse(try consumes(nil, "x"))
        XCTAssertFalse(try consumes(nil, "d", [.command, .option]))
        XCTAssertEqual(browser.shownSpace?.tabs.models.count, 5)
    }

    /// A store showing the first Space with `showing` as each Space's tab (the
    /// first tab when empty). `fallbackTabID` is the tab shown just before, so
    /// dismissing the shown tab returns to it.
    private func makeBatchStore(
        _ session: SessionState.Seed, showing tabs: [UUID: UUID] = [:], fallbackTabID: UUID? = nil
    ) -> BrowserStore {
        let preferences = BrowserLinkPreferenceStore()
        preferences.setBehavior(.followsMovedTabs, isOn: false)
        let spaceID = session.spaces[0].id
        let shown = tabs.isEmpty ? session.spaces[0].tabs.first.map { [spaceID: $0.id] } ?? [:] : tabs
        var opening = shown
        if let fallbackTabID { opening[spaceID] = fallbackTabID }
        let browser = BrowserStore(seed: session, showing: spaceID, tabs: opening, linkPreferences: preferences)
        if fallbackTabID != nil, let shownTab = shown[spaceID] { browser.activateSessionTab(shownTab, in: spaceID) }
        return browser
    }

    /// Organizes a fixture through the store's commands in its first Space.
    private func organized(
        _ session: SessionState.Seed, _ build: (BrowserStore, SpaceModel) throws -> Void
    ) throws -> SessionState.Seed {
        let browser = makeBatchStore(session)
        try build(browser, try XCTUnwrap(browser.shownSpace))
        return browser.sessionSeed
    }

    private func makeSession(count: Int) -> SessionState.Seed {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = (0..<count).map { index in
            TabState.Seed(
                title: "Tab \(index)", url: URL(string: "https://example.com/\(index)"), symbol: "globe",
                placement: .current)
        }
        // A session as the core opens it names its launch Space.
        return SessionState.Seed(spaces: [space], defaultSpaceID: space.id)
    }
}
