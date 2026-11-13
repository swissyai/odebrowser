import Foundation
import XCTest

@testable import Ode

/// The on-device service is a real system boundary. These controlled replies
/// protect lifetime, privacy and input routing, not translated wording.
@MainActor
final class BrowserCommandPaletteTranslationTests: XCTestCase {
    // MARK: - Actions - Service lifetime

    func testALateNoncooperativeTranslationCannotReplaceANewerQuery() async throws {
        let started = expectation(description: "Service requested")
        let gate = PaletteTranslationGate(started: started)
        let model = makeModel(translate: { await gate.translate($0) })
        defer { model.stop() }
        model.query = "translate hello to French"
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.items.first?.row.kind, .search)
        XCTAssertEqual(model.selectedResultIndex, 0)
        let pending = await pendingResults(of: model)

        model.query = "5 km in miles"
        await model.waitForPendingResults()
        await gate.finish(text: "late service output")
        await pending.value
        XCTAssertEqual(model.items.first { $0.row.card != nil }?.row.card?.kind, .conversion)
        XCTAssertFalse(model.items.contains { $0.row.card?.value == "late service output" })
    }

    func testEndingPresentationClearsQueryAndDropsNoncooperativeTranslation() async throws {
        let started = expectation(description: "Service requested")
        let gate = PaletteTranslationGate(started: started)
        let model = makeModel(translate: { await gate.translate($0) })
        model.query = "translate private words to French"
        await fulfillment(of: [started], timeout: 2)
        let pending = await pendingResults(of: model)
        model.dismiss()
        model.stop()
        await gate.finish(text: "late private service output")
        await pending.value

        XCTAssertTrue(model.query.isEmpty)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.translationPreparation)
        XCTAssertTrue(model.completionEditing.text.isEmpty)
    }

    func testMarkedTextCancelsPendingWorkAndNeverStartsAnotherServiceRequest() async throws {
        let started = expectation(description: "Service requested")
        let gate = PaletteTranslationGate(started: started)
        let model = makeModel(translate: { await gate.translate($0) })
        defer { model.stop() }
        model.query = "translate hello to French"
        await fulfillment(of: [started], timeout: 2)
        let pending = await pendingResults(of: model)
        model.updateCompletionEditing(text: "日本", selection: NSRange(location: 2, length: 0), isComposing: true)
        model.pressReturn()
        await gate.finish(text: "stale service output")
        await pending.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.completionEditing.isComposing)
        let requestCount = await gate.count()
        XCTAssertEqual(requestCount, 1)

        model.updateCompletionEditing(text: "日本", selection: NSRange(location: 2, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertEqual(model.query, "日本")
        XCTAssertFalse(model.items.contains { $0.row.card?.kind == .translation })
    }

    func testALostSourceCannotReceiveAServiceAnswer() async throws {
        let started = expectation(description: "Service requested")
        let gate = PaletteTranslationGate(started: started)
        var available = true
        let model = makeModel(isSourceAvailable: { _ in available }, translate: { await gate.translate($0) })
        defer { model.stop() }
        model.query = "translate hello to French"
        await fulfillment(of: [started], timeout: 2)
        available = false
        await gate.finish(text: "wrong window output")
        await model.waitForPendingResults()
        XCTAssertFalse(model.items.contains { $0.row.card?.value == "wrong window output" })
    }

    func testSourceAvailabilityRecoveryKeepsAMountedEditorUsable() async throws {
        var available = true
        let calls = PaletteTranslationCalls()
        let model = makeModel(
            isSourceAvailable: { _ in available },
            translate: { lookup in
                await calls.record(lookup)
                return PaletteTranslationResult(
                    lookup: lookup, sourceLanguage: "en", text: "service output", status: .translated)
            })
        defer { model.stop() }
        model.query = "translate hello to French"
        await model.waitForPendingResults()
        available = false
        model.sourceAvailabilityChanged(false)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.query, "translate hello to French")
        XCTAssertNil(model.translationPreparation)
        available = true
        model.sourceAvailabilityChanged(true)
        await model.waitForPendingResults()
        XCTAssertEqual(model.items.first { $0.row.card?.kind == .translation }?.row.card?.value, "service output")
        let count = await calls.requests.count
        XCTAssertEqual(count, 2)
        model.query = "5 km in miles"
        await model.waitForPendingResults()
        XCTAssertEqual(model.items.first { $0.row.card != nil }?.row.card?.kind, .conversion)
    }

    // MARK: - Actions - Authorization and input

    func testMissingLanguagesDoNotCreateAPermissionHostUntilAnExplicitActionAndRetryIsPossible() async throws {
        let model = makeModel { lookup in
            PaletteTranslationResult(lookup: lookup, sourceLanguage: "en", text: nil, status: .notInstalled)
        }
        defer { model.stop() }
        model.query = "translate hello to French"
        await model.waitForPendingResults()
        XCTAssertNil(model.translationPreparation, "Typing must not create a download-capable session")
        XCTAssertNil(model.items.first { $0.row.card?.kind == .translation }?.row.card?.value)
        XCTAssertTrue(model.canRetryTranslation)
        XCTAssertTrue(model.canDownloadTranslationLanguages)
        model.downloadTranslationLanguages()
        await model.waitForPendingResults()
        XCTAssertNotNil(model.translationPreparation)
        model.query = "ordinary search"
        XCTAssertNil(model.translationPreparation, "Editing revokes the pending permission request")
        await model.waitForPendingResults()
    }

    func testRapidEditingDebouncesServiceWorkWithoutBlockingNativeQueryUpdates() async throws {
        let calls = PaletteTranslationCalls()
        let model = makeModel(debounce: .milliseconds(40)) { lookup in
            await calls.record(lookup)
            return PaletteTranslationResult(lookup: lookup, sourceLanguage: "en", text: nil, status: .failed)
        }
        defer { model.stop() }
        for index in 0..<30 { model.query = "translate phrase \(index) to French" }
        XCTAssertEqual(model.query, "translate phrase 29 to French")
        await model.waitForPendingResults()
        let requested = await calls.requests
        XCTAssertEqual(requested.map(\.text), ["phrase 29"])
        XCTAssertNil(model.translationPreparation)
        model.retryTranslation()
        await model.waitForPendingResults()
        let retryCount = await calls.requests.count
        XCTAssertEqual(retryCount, 2)
    }

    func testReturnKeepsSearchingWhileTranslationIsPendingAndCopyUsesOnlyServiceOutput() async throws {
        var opened: [URL] = []
        let model = makeModel(
            openURL: { _, url, _ in
                opened.append(url)
                return true
            },
            translate: { lookup in
                PaletteTranslationResult(
                    lookup: lookup, sourceLanguage: "en", text: "service output 👋", status: .translated)
            })
        model.query = "translate hello to French"
        await model.waitForPendingResults()
        model.pressReturn()
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened.first?.absoluteString.contains("translate%20hello%20to%20French") == true)

        var copied: [String] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in }, copy: { copied.append($0) })
        let copyModel = makeModel(commands: commands) { lookup in
            PaletteTranslationResult(
                lookup: lookup, sourceLanguage: "en", text: "service output 👋", status: .translated)
        }
        copyModel.query = "translate hello to French"
        await copyModel.waitForPendingResults()
        let item = try XCTUnwrap(copyModel.items.first { $0.row.card?.kind == .translation })
        copyModel.selectResult(at: item.index)
        copyModel.pressReturn()
        XCTAssertEqual(copied, ["service output 👋"])
    }

    // MARK: - Actions - Fixtures

    private func pendingResults(of model: BrowserCommandPaletteModel) async -> Task<Void, Never> {
        let ready = expectation(description: "Observing the current request")
        let pending = Task { @MainActor in
            ready.fulfill()
            await model.waitForPendingResults()
        }
        await fulfillment(of: [ready], timeout: 2)
        return pending
    }

    private func makeModel(
        commands: BrowserCommandPaletteCommandRegistry? = nil,
        debounce: Duration = .zero,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool = { _ in true },
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool = { _, _, _ in false
        },
        translate: @escaping @Sendable (PaletteTranslationLookup) async -> PaletteTranslationResult
    ) -> BrowserCommandPaletteModel {
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(name: "Translation", symbol: "translate", accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        return BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: commands,
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: debounce,
                fetchSuggestions: { url in
                    XCTAssertFalse(
                        url.absoluteString.contains("translate"), "Translation text must not reach suggestions")
                    return []
                },
                lookUpDefinition: { _ in nil },
                fetchWebSummary: { _ in
                    XCTFail("Translation text must not reach web answers")
                    return nil
                },
                translate: translate),
            isSourceAvailable: isSourceAvailable, selectTab: { _, _ in false }, openURL: openURL, dismiss: {})
    }
}

private actor PaletteTranslationGate {
    // MARK: - Variables

    private let started: XCTestExpectation
    private var pending: (PaletteTranslationLookup, CheckedContinuation<PaletteTranslationResult, Never>)?
    private var requests = 0

    // MARK: - Initializers

    init(started: XCTestExpectation) { self.started = started }

    // MARK: - Actions - Service

    func translate(_ lookup: PaletteTranslationLookup) async -> PaletteTranslationResult {
        requests += 1
        return await withCheckedContinuation { continuation in
            pending = (lookup, continuation)
            started.fulfill()
        }
    }

    func finish(text: String) {
        guard let pending else { return }
        self.pending = nil
        pending.1.resume(
            returning: PaletteTranslationResult(
                lookup: pending.0, sourceLanguage: "en", text: text, status: .translated))
    }

    func count() -> Int { requests }
}

private actor PaletteTranslationCalls {
    // MARK: - Variables

    private(set) var requests: [PaletteTranslationLookup] = []

    // MARK: - Actions - Service

    func record(_ lookup: PaletteTranslationLookup) { requests.append(lookup) }
}
