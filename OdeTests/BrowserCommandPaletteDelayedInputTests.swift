import AppKit
import XCTest

@testable import Ode

/// A key belongs to the text it was pressed for, never the preceding rows.
@MainActor
final class BrowserCommandPaletteDelayedInputTests: XCTestCase {
    // MARK: - Actions - Input

    func testReturnDoesNotOpenAnOldAddressWhenTheAnswerTakesLongerThanTheKeyWait() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/path", delay: .milliseconds(600))
        defer { fixture.close() }
        fixture.type("https://latest.example.test/path")
        fixture.pressReturn()

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(fixture.opened.isEmpty, "Return must not open the address from the previous query")
        XCTAssertTrue(fixture.selected.isEmpty)
        await fixture.model.waitForPendingResults()
        XCTAssertTrue(fixture.opened.isEmpty, "An expired key must not activate later")

        fixture.pressReturn()
        XCTAssertEqual(fixture.opened.map(\.absoluteString), ["https://latest.example.test/path"])
    }

    func testReturnDoesNotSwitchToAnOldTabWhileAChangedQueryIsPending() async throws {
        let fixture = try makeEditor(initialQuery: "", delay: .milliseconds(600))
        defer { fixture.close() }
        XCTAssertEqual(fixture.model.items.first?.row.tabID, fixture.targetID)
        fixture.type("new search words")
        fixture.pressReturn()

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(fixture.selected.isEmpty, "Return must not switch to the tab from the resting rows")
        XCTAssertTrue(fixture.opened.isEmpty)
        await fixture.model.waitForPendingResults()
        XCTAssertTrue(fixture.selected.isEmpty)
        XCTAssertTrue(fixture.opened.isEmpty)

        fixture.pressReturn()
        XCTAssertEqual(fixture.opened.count, 1)
        XCTAssertTrue(fixture.opened.first?.absoluteString.contains("new%20search%20words") == true)
    }

    func testEditingAgainCancelsThePendingReturnRatherThanApplyingItToAnotherQuery() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/", delay: .milliseconds(100))
        defer { fixture.close() }
        fixture.type("first search words")
        fixture.pressReturn()
        fixture.type("latest search words")
        await fixture.model.waitForPendingResults()

        XCTAssertTrue(fixture.opened.isEmpty, "The earlier Return does not belong to the edited text")
        XCTAssertTrue(fixture.selected.isEmpty)
        fixture.pressReturn()
        XCTAssertEqual(fixture.opened.count, 1)
        XCTAssertTrue(fixture.opened.first?.absoluteString.contains("latest%20search%20words") == true)
    }

    func testReturnStillRunsTheCurrentQueryWhenItsAnswerArrivesWithinTheWait() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/", delay: .milliseconds(50))
        defer { fixture.close() }
        fixture.type("https://latest.example.test/")
        fixture.pressReturn()
        await fixture.model.waitForPendingResults()

        XCTAssertEqual(fixture.opened.map(\.absoluteString), ["https://latest.example.test/"])
        XCTAssertTrue(fixture.selected.isEmpty)
    }

    func testMarkedTextKeepsReturnAndDeletionInTheEditorAndCancelsAnEarlierReturn() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/", delay: .milliseconds(100))
        defer { fixture.close() }
        fixture.type("pending words")
        fixture.pressReturn()
        fixture.editor.setMarkedText(
            "é", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: fixture.editor.string.utf16.count, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertTrue(fixture.editor.hasMarkedText())
        XCTAssertFalse(
            fixture.coordinator.perform(#selector(NSResponder.insertNewline(_:)), in: fixture.editor, modifiers: []))
        XCTAssertFalse(
            fixture.coordinator.perform(#selector(NSResponder.deleteBackward(_:)), in: fixture.editor, modifiers: []))
        await fixture.model.waitForPendingResults()

        XCTAssertTrue(fixture.opened.isEmpty, "Beginning composition cancels a Return queued for unmarked text")
        XCTAssertTrue(fixture.selected.isEmpty)
    }

    func testNativeDeletionCancelsAReturnQueuedForTheLongerQuery() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/", delay: .milliseconds(100))
        defer { fixture.close() }
        fixture.type("new search wordsx")
        fixture.pressReturn()
        XCTAssertFalse(
            fixture.coordinator.perform(#selector(NSResponder.deleteBackward(_:)), in: fixture.editor, modifiers: []))
        fixture.editor.deleteBackward(nil)
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()

        XCTAssertEqual(fixture.model.query, "new search words")
        XCTAssertTrue(fixture.opened.isEmpty)
        fixture.pressReturn()
        XCTAssertEqual(fixture.opened.count, 1)
        XCTAssertTrue(fixture.opened.first?.absoluteString.contains("new%20search%20words") == true)
    }

    func testReturnFollowsTheSameQueryIntoItsExplicitTabScope() async throws {
        let fixture = try makeEditor(initialQuery: "", delay: .milliseconds(50), targetTitle: "CAFÉ notes")
        defer { fixture.close() }
        fixture.type("@tabs cafe\u{301}")
        fixture.pressReturn()
        await fixture.model.waitForPendingResults()
        await fixture.model.waitForPendingResults()

        XCTAssertEqual(fixture.model.activeScope, .tabs)
        XCTAssertEqual(fixture.selected, [fixture.targetID])
        XCTAssertTrue(fixture.opened.isEmpty)
    }

    func testDismissingThePaletteCancelsAPendingReturn() async throws {
        let fixture = try makeEditor(initialQuery: "https://old.example.test/", delay: .milliseconds(100))
        defer { fixture.close() }
        fixture.type("https://latest.example.test/")
        fixture.pressReturn()
        fixture.model.dismiss()
        await fixture.model.waitForPendingResults()

        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertTrue(fixture.selected.isEmpty)
    }

    // MARK: - Actions - Fixtures

    private func makeEditor(
        initialQuery: String, delay: Duration, targetTitle: String = "Older target"
    ) throws -> DelayedPaletteEditor {
        let source = TabState.Seed.startPage()
        let target = TabState.Seed(
            title: targetTitle, url: URL(string: "https://target.example.test/"), placement: .current)
        let space = SpaceState.Seed(
            name: "Input", symbol: "command", accent: .indigo, folders: [], tabs: [source, target])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: source.id])
        let core = browser.core
        let recorder = PaletteInputRecorder()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: source.id,
            initialQuery: initialQuery, commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, lookUpDefinition: { _ in nil }, fetchWebSummary: { _ in nil },
                answer: { question in
                    try? await Task.sleep(for: delay)
                    return try? core.query(question)
                }),
            isSourceAvailable: { _ in true },
            selectTab: { _, target in
                recorder.selected.append(target.tabID)
                return true
            },
            openURL: { _, url, _ in
                recorder.opened.append(url)
                return true
            }, dismiss: {})
        return try DelayedPaletteEditor(model: model, targetID: target.id, recorder: recorder)
    }
}

@MainActor
private final class PaletteInputRecorder {
    // MARK: - Variables

    var opened: [URL] = []
    var selected: [UUID] = []
}

@MainActor
private final class DelayedPaletteEditor {
    // MARK: - Variables

    let model: BrowserCommandPaletteModel
    let targetID: UUID
    let window: NSWindow
    let field: NSTextField
    let coordinator: BrowserPlatformCommandPaletteField.Coordinator
    let editor: NSTextView
    private let recorder: PaletteInputRecorder
    var opened: [URL] { recorder.opened }
    var selected: [UUID] { recorder.selected }

    // MARK: - Initializers

    init(model: BrowserCommandPaletteModel, targetID: UUID, recorder: PaletteInputRecorder) throws {
        self.model = model
        self.targetID = targetID
        self.recorder = recorder
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: .overlay, identifier: "delayed-input", focused: false)
        coordinator = view.makeCoordinator()
        field = view.makeField(coordinator: coordinator)
        window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 80), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        field.frame = NSRect(x: 10, y: 20, width: 380, height: 32)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        field.selectText(nil)
        editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    }

    // MARK: - Actions - Editing

    func type(_ text: String) {
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        coordinator.editingChanged()
    }

    func pressReturn() {
        XCTAssertTrue(coordinator.perform(#selector(NSResponder.insertNewline(_:)), in: editor, modifiers: []))
    }

    func close() {
        BrowserPlatformCommandPaletteField.dismantleNSView(field, coordinator: coordinator)
        window.close()
    }
}
