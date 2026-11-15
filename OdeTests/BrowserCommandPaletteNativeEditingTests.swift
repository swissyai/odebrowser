import AppKit
import SwiftUI
import XCTest

@testable import Ode

@MainActor
final class BrowserCommandPaletteNativeEditingTests: XCTestCase {
    func testDismantlingFieldReleasesCompletionHostWithoutDisruptingItsSuccessor() async throws {
        weak var oldLabel: BrowserPlatformCommandPaletteField.CompletionLabel?
        let successor = try autoreleasepool {
            let fixture = makeEditor()
            let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
            fixture.coordinator.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: fixture.field))
            oldLabel = fixture.coordinator.suffixLabel
            XCTAssertTrue(oldLabel?.superview === editor)
            let unrelated = NSView()
            editor.addSubview(unrelated)

            // Removing a representable need not send the text delegate an
            // end-editing callback. The shared editor outlives this field.
            BrowserPlatformCommandPaletteField.dismantleNSView(fixture.field, coordinator: fixture.coordinator)
            XCTAssertNil(oldLabel?.superview)
            XCTAssertNil(oldLabel?.nextResponder)
            XCTAssertNil(fixture.coordinator.field)
            XCTAssertNil(fixture.field.delegate)
            XCTAssertTrue(unrelated.superview === editor)
            let oldQuery = fixture.model.query
            editor.string = "detached editor text"
            NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: editor)
            XCTAssertEqual(fixture.model.query, oldQuery)

            let view = BrowserPlatformCommandPaletteField(
                model: fixture.model, presentation: .overlay, identifier: "successor-field", focused: false)
            let coordinator = view.makeCoordinator()
            let field = view.makeField(coordinator: coordinator)
            field.frame = fixture.field.frame
            fixture.window.contentView?.addSubview(field)
            fixture.window.makeFirstResponder(field)
            field.selectText(nil)
            let nextEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            coordinator.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: field))
            XCTAssertTrue(nextEditor === editor)
            XCTAssertTrue(coordinator.suffixLabel.superview === editor)

            // Delayed disposal of an old field must not clear a newer field's
            // callback, responder link, delegate or selection observer.
            BrowserPlatformCommandPaletteField.dismantleNSView(fixture.field, coordinator: fixture.coordinator)
            XCTAssertTrue(field.delegate === coordinator)
            XCTAssertTrue(coordinator.suffixLabel.nextResponder === editor)
            editor.insertText("exa", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            coordinator.editingChanged()
            return (
                window: fixture.window, field: field, coordinator: coordinator, editor: editor, model: fixture.model
            )
        }
        defer {
            BrowserPlatformCommandPaletteField.dismantleNSView(successor.field, coordinator: successor.coordinator)
            successor.window.close()
        }
        // The core answers off the main thread; the completion arrives with it.
        await successor.model.waitForPendingResults()
        XCTAssertTrue(successor.model.acceptURLCompletion())
        XCTAssertEqual(successor.editor.string, "example.com")

        // The same coordinator can detach and rejoin normal editing.
        successor.coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
        XCTAssertNil(successor.coordinator.suffixLabel.nextResponder)
        successor.coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification))
        XCTAssertTrue(successor.coordinator.suffixLabel.superview === successor.editor)
        XCTAssertTrue(successor.coordinator.suffixLabel.nextResponder === successor.editor)
        for _ in 0..<20 where oldLabel != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(oldLabel, "The surviving field editor must not retain a disposed completion hosting view")
        XCTAssertTrue(successor.field.currentEditor() === successor.editor)
    }

    func testNativeSelectionAndMarkedTextPreventAcceptanceWithoutConsumingArrows() async throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        editor.moveLeft(nil)
        fixture.coordinator.editingChanged()
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertNil(fixture.model.urlCompletion)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.setMarkedText(
            "m", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 3, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertNil(fixture.model.urlCompletion)
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertFalse(fixture.model.acceptURLCompletion())
        XCTAssertEqual(fixture.field.maximumNumberOfLines, 1)
        XCTAssertFalse(fixture.field.cell?.wraps ?? true)
        XCTAssertTrue(fixture.field.cell?.isScrollable ?? false)
    }

    func testRightArrowAcceptsOnlyAtTheEndAndPreservesSelectionCommands() async throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRightAndModifySelection(_:))))
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertEqual(editor.string, "example.com")
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }

    /// Control-A and Control-E send Option-Up's and Option-Down's commands.
    /// Only Option moves between result sections; Control keeps the line edges.
    func testControlParagraphCommandsKeepLineEdgesAndOptionMovesSections() async throws {
        let fixture = makeEditor(tabs: [
            TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current),
            TabState.Seed(title: "Docs", url: URL(string: "https://docs.example.com/"), placement: .current),
            TabState.Seed(
                title: "Saved note", url: URL(string: "https://notes.example.com/saved"), placement: .saved),
        ])
        defer {
            BrowserPlatformCommandPaletteField.dismantleNSView(fixture.field, coordinator: fixture.coordinator)
            fixture.window.close()
        }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        fixture.coordinator.controlTextDidBeginEditing(
            Notification(name: NSControl.textDidBeginEditingNotification, object: fixture.field))
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertNotNil(fixture.model.urlCompletion)
        XCTAssertTrue(
            fixture.coordinator.perform(
                #selector(NSResponder.moveToEndOfParagraph(_:)), in: editor, modifiers: .control))
        XCTAssertEqual(editor.string, "example.com")
        XCTAssertNil(fixture.model.urlCompletion)

        editor.insertText("docs", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertGreaterThanOrEqual(fixture.model.groups.count, 2)
        let start = fixture.model.selectedResultIndex
        XCTAssertTrue(
            fixture.coordinator.perform(
                #selector(NSResponder.moveToEndOfParagraph(_:)), in: editor, modifiers: .option))
        XCTAssertNotEqual(fixture.model.selectedResultIndex, start)
        XCTAssertTrue(
            fixture.coordinator.perform(
                #selector(NSResponder.moveToBeginningOfParagraph(_:)), in: editor, modifiers: .option))
        XCTAssertEqual(fixture.model.selectedResultIndex, start)
        XCTAssertFalse(
            fixture.coordinator.perform(
                #selector(NSResponder.moveToBeginningOfParagraph(_:)), in: editor, modifiers: .control))
        XCTAssertEqual(fixture.model.selectedResultIndex, start)
    }

    func testRapidCopyOrDismissAndNewTabStartsAFreshNativeQuery() async throws {
        for copiesAnswer in [true, false] {
            let fixture = try PaletteReopenFixture()
            defer { fixture.close() }
            let initial = try await fixture.readyEditor()
            fixture.type("12 * 3", into: initial)
            for _ in 0..<100 {
                await initial.coordinator.model.waitForPendingResults()
                if initial.coordinator.model.tabCopyCandidate?.row.card?.value == "36" { break }
                await Task.yield()
            }
            let candidate = try XCTUnwrap(
                initial.coordinator.model.tabCopyCandidate, "Focused numeric answer precondition")
            XCTAssertEqual(candidate.row.card?.value, "36")
            if copiesAnswer {
                XCTAssertTrue(
                    initial.coordinator.perform(#selector(NSResponder.insertTab(_:)), in: initial.editor, modifiers: [])
                )
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), "36")
                XCTAssertEqual(fixture.tour.step, .sidebar)
            } else {
                // The real palette's Exit command calls this same bound action.
                initial.coordinator.model.dismiss()
            }
            XCTAssertFalse(fixture.root.chrome.isCommandPalettePresented)
            XCTAssertTrue(fixture.commands.perform(.newTab).wasPerformed)
            // AppKit delivers the next text event after normal host layout;
            // closing and reopening above deliberately shared one render turn.
            fixture.host.layoutSubtreeIfNeeded()
            let reopened = try fixture.currentEditor()
            XCTAssertEqual(reopened.coordinator.model.query, "")
            XCTAssertEqual(reopened.editor.string, "")
            fixture.type("8 * 7", into: reopened)
            XCTAssertEqual(reopened.editor.string, "8 * 7")
            XCTAssertEqual(reopened.coordinator.model.query, "8 * 7")
            for _ in 0..<100 {
                await reopened.coordinator.model.waitForPendingResults()
                if reopened.coordinator.model.tabCopyCandidate?.row.card?.value == "56" { break }
                await Task.yield()
            }
            XCTAssertEqual(reopened.coordinator.model.tabCopyCandidate?.row.card?.value, "56")
            XCTAssertEqual(reopened.editor.string, "8 * 7")
            if !copiesAnswer { XCTAssertTrue(fixture.tour.answerIsReady) }
        }
    }

    func testOpenLocationReopensWithItsAddressSeedAndAnOrdinaryRenderKeepsTheDraft() async throws {
        let fixture = try PaletteReopenFixture()
        defer { fixture.close() }
        _ = try await fixture.readyEditor()
        let address = "https://example.com/original"
        fixture.root.chrome.openLocation(address)
        fixture.host.layoutSubtreeIfNeeded()
        let location = try fixture.currentEditor()
        XCTAssertEqual(location.editor.string, address)
        XCTAssertEqual(location.coordinator.model.query, address)
        location.editor.selectAll(nil)
        let draft = "https://edited.example.test/path"
        fixture.type(draft, into: location)
        fixture.host.rootView = PaletteReopenSurface(model: fixture.root)
        fixture.host.layoutSubtreeIfNeeded()
        let retained = try fixture.currentEditor()
        XCTAssertTrue(retained.coordinator.model === location.coordinator.model)
        XCTAssertEqual(retained.editor.string, draft)
        XCTAssertEqual(retained.coordinator.model.query, draft)
        fixture.root.chrome.dismissCommandPalette()
        fixture.root.chrome.openLocation(address)
        fixture.host.layoutSubtreeIfNeeded()
        let reopened = try fixture.currentEditor()
        XCTAssertEqual(reopened.editor.string, address)
        XCTAssertEqual(reopened.coordinator.model.query, address)
    }

    private func makeEditor(
        tabs: [TabState.Seed] = [
            TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        ]
    ) -> (
        window: NSWindow, field: NSTextField, coordinator: BrowserPlatformCommandPaletteField.Coordinator,
        model: BrowserCommandPaletteModel
    ) {
        let tab = tabs[0]
        let space = SpaceState.Seed(
            name: "Test", symbol: "globe", accent: .indigo, folders: [],
            tabs: tabs)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: .overlay, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        field.frame = NSRect(x: 10, y: 20, width: 300, height: 32)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        field.selectText(nil)
        return (window, field, coordinator, model)
    }
}

/// A field that counts how often its placeholder is set.
private final class PlaceholderCountingTextField: NSTextField {
    var placeholderSets = 0

    override var placeholderString: String? {
        didSet { placeholderSets += 1 }
    }
}

@MainActor
final class BrowserNativeEmojiTextFieldEditingTests: XCTestCase {
    /// Updating the field while it edits leaves its placeholder alone, so
    /// AppKit never restarts the editing it is in.
    func testUpdatesWhileEditingSetThePlaceholderOnce() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless], backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = PlaceholderCountingTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        field.selectText(nil)
        let editor = field.currentEditor()

        for _ in 0..<5 {
            BrowserNativeEmojiTextField.show(text: "", placeholder: "Emoji", in: field)
        }

        XCTAssertEqual(field.placeholderSets, 1)
        XCTAssertNotNil(field.currentEditor())
        XCTAssertTrue(field.currentEditor() === editor)
    }
}

@MainActor
private struct PaletteReopenSurface: View {
    let model: BrowserRootModel
    @Namespace private var namespace

    var body: some View {
        BrowserRootCommandPaletteLayer(model: model, shortcuts: nil, commandSurfaceNamespace: namespace)
    }
}

@MainActor
private final class PaletteReopenFixture {
    typealias Editor = (
        field: NSTextField, editor: NSTextView, coordinator: BrowserPlatformCommandPaletteField.Coordinator
    )

    let root: BrowserRootModel
    let tour: BrowserGettingStartedTour
    let commands: BrowserCommandPaletteCommandRegistry
    let host: NSHostingView<PaletteReopenSurface>
    private let window: NSWindow
    private let clipboard: [NSPasteboardItem]

    init() throws {
        clipboard = (NSPasteboard.general.pasteboardItems ?? []).map { source in
            let item = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) { item.setData(data, forType: type) }
            }
            return item
        }
        let browser = BrowserStore(seed: .preview)
        _ = BrowserShortcutStore(core: browser.core)
        _ = try XCTUnwrap(browser.openGettingStarted())
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        pages.select()
        root = BrowserRootModel(
            browser: browser, pages: pages, chrome: BrowserChromeState(),
            spaceAccess: BrowserSpaceAccessController(), windowState: nil,
            startupBehavior: .lastActiveTab, persistedSidebarWidth: 260)
        tour = BrowserGettingStartedTour(defaults: nil, browser: browser, chrome: root.chrome)
        root.chrome.gettingStartedTour = tour
        tour.start(try XCTUnwrap(browser.shownTabAssignment), automatically: false)
        commands = root.paletteRegistry(windows: nil, layoutDirection: .leftToRight, shortcuts: nil)
        host = NSHostingView(rootView: PaletteReopenSurface(model: root))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        XCTAssertTrue(commands.perform(.newTab).wasPerformed)
        host.layoutSubtreeIfNeeded()
    }

    func close() {
        window.close()
        root.pages.reconcile(validTabIDs: [])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(clipboard)
    }

    func readyEditor() async throws -> Editor {
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if let field = findField(in: host), field.currentEditor() != nil { return try currentEditor() }
            await Task.yield()
        }
        return try currentEditor()
    }

    func currentEditor() throws -> Editor {
        let field = try XCTUnwrap(findField(in: host))
        return (
            field, try XCTUnwrap(field.currentEditor() as? NSTextView),
            try XCTUnwrap(field.delegate as? BrowserPlatformCommandPaletteField.Coordinator)
        )
    }

    func type(_ text: String, into target: Editor) {
        if !target.coordinator.model.isFieldFocused {
            // The offscreen host has a field editor without a key-window
            // begin-editing notification; deliver AppKit's delegate boundary.
            target.coordinator.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: target.field))
        }
        target.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        target.coordinator.editingChanged()
    }

    private func findField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.accessibilityIdentifier() == "command-palette-field",
            field.currentEditor() != nil
        {
            return field
        }
        for child in view.subviews {
            if let field = findField(in: child) { return field }
        }
        return nil
    }
}
