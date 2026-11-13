import AppKit
import SwiftUI

/// Routes sidebar selection keys and modifier clicks before row activation.
struct BrowserTabSelectionMonitor: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let assignment: BrowserSpaceRuntimeAssignment
    let activate: (UUID) -> Void
    var ownsFocus = false

    var body: some View {
        GeometryReader { proxy in
            Bridge(
                browser: browser, sidebarInteraction: sidebarInteraction, spaceAccess: spaceAccess,
                assignment: assignment, activate: activate, ownsFocus: ownsFocus,
                globalFrame: proxy.frame(in: .global))
        }
    }

    private struct Bridge: NSViewRepresentable {
        let browser: BrowserStore
        let sidebarInteraction: BrowserSidebarInteractionState
        let spaceAccess: BrowserSpaceAccessController
        let assignment: BrowserSpaceRuntimeAssignment
        let activate: (UUID) -> Void
        let ownsFocus: Bool
        let globalFrame: CGRect

        func makeNSView(context: Context) -> SelectionView { SelectionView() }

        func updateNSView(_ view: SelectionView, context: Context) {
            view.browser = browser
            view.sidebarInteraction = sidebarInteraction
            view.spaceAccess = spaceAccess
            view.assignment = assignment
            view.activate = activate
            view.globalFrame = globalFrame
            if ownsFocus, browser.selectedSpaceID == assignment.spaceID,
                view.window?.attachedSheet == nil,
                view.window?.firstResponder !== view
            {
                view.window?.makeFirstResponder(view)
            }
        }

        static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stop() }
    }

    /// Where an arrow, Home or End key moves the sidebar's keyboard focus:
    /// one item along, or with Command, Home or End, to the first or last.
    private struct FocusStep {
        let backwards: Bool
        let toEdge: Bool

        init?(key: BrowserShortcutHardwareKeyCode, command: Bool) {
            switch key {
            case .leftArrow, .upArrow: (backwards, toEdge) = (true, command)
            case .rightArrow, .downArrow: (backwards, toEdge) = (false, command)
            case .home: (backwards, toEdge) = (true, true)
            case .end: (backwards, toEdge) = (false, true)
            default: return nil
            }
        }

        func index(from current: Int, count: Int) -> Int {
            if toEdge { return backwards ? 0 : count - 1 }
            return min(max(current + (backwards ? -1 : 1), 0), count - 1)
        }
    }

    final class SelectionView: NSView {
        weak var browser: BrowserStore?
        weak var sidebarInteraction: BrowserSidebarInteractionState?
        weak var spaceAccess: BrowserSpaceAccessController?
        var assignment: BrowserSpaceRuntimeAssignment?
        var activate: ((UUID) -> Void)?
        var globalFrame: CGRect = .zero
        private var monitor: Any?
        private(set) var windowObservers: [NSObjectProtocol] = []
        private(set) var consumedDown = false
        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resignFirstResponder() -> Bool {
            browser?.tabMultiSelection.ownsKeyboardFocus = false
            return super.resignFirstResponder()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.sidebarInteraction?.cancel() }
                    })
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown,
            ]) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers.removeAll()
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard let eventWindow = window, event.window === eventWindow else { return event }
            if event.type == .leftMouseDragged || event.type == .leftMouseUp { forwardPointerContinuation(event) }
            if event.type == .leftMouseDragged { return event }
            guard let browser, let sidebarInteraction, let spaceAccess, let assignment,
                browser.selectedSpaceID == assignment.spaceID
            else { return event }
            guard
                browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
            else {
                browser.tabMultiSelection.clear()
                return event
            }
            switch event.type {
            case .keyDown:
                return handleKeyDown(event, browser: browser, reorder: sidebarInteraction.sidebarReorderState)
            case .leftMouseUp: return handleMouseUp(event)
            default: return handleMouseDown(event, browser: browser, assignment: assignment)
            }
        }

        /// A drag that began on a row keeps reaching the reorder state while
        /// the pointer travels over other views of this window.
        private func forwardPointerContinuation(_ event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            let global = CGPoint(x: globalFrame.minX + local.x, y: globalFrame.minY + local.y)
            sidebarInteraction?.sidebarReorderState.forwardPointerContinuation(
                at: global, released: event.type == .leftMouseUp, eventTimestamp: event.timestamp)
        }

        /// Escape drops a lift in flight wherever focus is; every other key
        /// belongs to the sidebar only while this view holds focus.
        private func handleKeyDown(
            _ event: NSEvent, browser: BrowserStore, reorder: BrowserSidebarReorderState
        ) -> NSEvent? {
            if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .escape, reorder.hasLiftInFlight {
                reorder.cancel()
                browser.tabMultiSelection.clear()
                return nil
            }
            guard window?.firstResponder === self else { return event }
            return handleKey(event, browser: browser)
        }

        /// Swallows the mouse-up of a modifier click this view already took.
        private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
            guard consumedDown else { return event }
            consumedDown = false
            return nil
        }

        private func handleMouseDown(
            _ event: NSEvent, browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment
        ) -> NSEvent? {
            let selection = browser.tabMultiSelection
            guard let window,
                let id = BrowserNativeTabSelectionTarget.TargetView.item(
                    at: event.locationInWindow, in: window, browser: browser, assignment: assignment)
            else {
                selection.clear()
                return event
            }
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                if !selection.contains(id) { selection.clear() }
                return event
            }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if command || shift {
                selection.click(
                    id, units: units, command: command, shift: shift,
                    activeItem: browser.selectedTabID(in: assignment.spaceID).map(BrowserSelectionItemID.tab))
                window.makeFirstResponder(self)
                consumedDown = true
                return nil
            }
            // Preserve a selected set on mouse-down so dragging it carries the
            // set. The activation button collapses it only after a plain click.
            if !selection.contains(id) { selection.click(id, units: units) }
            return event
        }

        private func handleKey(_ event: NSEvent, browser: BrowserStore) -> NSEvent? {
            guard let sidebarInteraction else { return event }
            let selection = browser.tabMultiSelection
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .escape {
                sidebarInteraction.sidebarReorderState.cancel()
                selection.clear()
                return nil
            }
            let handled =
                selectAll(event, selection: selection, units: units)
                || performBatchShortcut(event, browser: browser)
                || moveFocus(event, browser: browser, units: units)
                || activateFocusedItem(event, browser: browser)
            return handled ? nil : event
        }

        /// Command-A selects every item and Shift-Command-A clears them.
        private func selectAll(
            _ event: NSEvent, selection: BrowserTabMultiSelection, units: [[BrowserSelectionItemID]]
        ) -> Bool {
            guard event.modifierFlags.contains(.command), BrowserShortcutKey(event: event) == .character("a")
            else { return false }
            if event.modifierFlags.contains(.shift) { selection.clear() } else { selection.selectAll(units: units) }
            return true
        }

        /// Command with C, D, W or Delete copies, duplicates, closes or
        /// deletes the selection captured around the focused item.
        private func performBatchShortcut(_ event: NSEvent, browser: BrowserStore) -> Bool {
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                let id = browser.tabMultiSelection.focusedItem,
                let request = BrowserSidebarSelection.capture(for: id, in: browser), let spaceAccess
            else { return false }
            let actions = BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess)
            switch BrowserShortcutKey(event: event) {
            case .character("c"): actions.copyLinks(request)
            case .character("d"): actions.perform(browser.duplicating(request), for: request)
            case .character("w"): actions.perform(browser.closing(request), for: request)
            default:
                guard BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .delete else { return false }
                actions.perform(browser.deleting(request), for: request)
            }
            return true
        }

        /// The arrows step the focus one item, Home, End and Command-arrows
        /// jump to an end, and Shift extends the selection as it moves.
        private func moveFocus(_ event: NSEvent, browser: BrowserStore, units: [[BrowserSelectionItemID]]) -> Bool {
            guard let key = BrowserShortcutHardwareKeyCode(rawValue: event.keyCode),
                let step = FocusStep(key: key, command: event.modifierFlags.contains(.command)), !units.isEmpty
            else { return false }
            let selection = browser.tabMultiSelection
            let shift = event.modifierFlags.contains(.shift)
            let current =
                units.firstIndex { $0.contains(selection.focusedItem ?? selection.anchorItem ?? units[0][0]) } ?? 0
            let target = units[step.index(from: current, count: units.count)][0]
            selection.click(
                target, units: units, shift: shift,
                activeItem: assignment.flatMap { browser.selectedTabID(in: $0.spaceID) }.map(
                    BrowserSelectionItemID.tab))
            if !shift { selection.selectForKeyboard(target, units: units) }
            return true
        }

        /// Return activates the focused tab, or opens or closes the focused folder.
        private func activateFocusedItem(_ event: NSEvent, browser: BrowserStore) -> Bool {
            guard BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .returnKey,
                let id = browser.tabMultiSelection.focusedItem
            else { return false }
            if let tabID = id.tabID { activate?(tabID) }
            if let folderID = id.folderID, let folder = browser.shownSpace?.folders.model(folderID) {
                browser.setFolderCollapsed(folderID, in: browser.selectedSpaceID, isCollapsed: !folder.isCollapsed)
            }
            return true
        }

        override func selectAll(_ sender: Any?) {
            guard let browser, sidebarInteraction != nil else { return }
            browser.tabMultiSelection.selectAll(
                units: BrowserSidebarSelection.itemUnits(in: browser))
        }
    }
}
