import Foundation
import XCTest

@testable import Ode

/// The local-model port is a system boundary. Controlled output proves
/// routing, cancellation and ownership, not Apple's answer quality.
@MainActor
final class BrowserCommandPalettePrivateAnswerTests: XCTestCase {
    // MARK: - Actions - Routing

    func testEligiblePreviewNeverCallsOptedInRemoteClientsOrActsWhileTypingAndCopyIsExplicit() async throws {
        var copied: [String] = []
        var opened: [URL] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in XCTFail("Typing must not execute commands") }, copy: { copied.append($0) })
        let model = try makeModel(
            commands: commands,
            openURL: {
                opened.append($0)
                return true
            },
            generate: { lookup in
                PaletteGenerativeResult(lookup: lookup, text: "Synthetic local answer", status: .answered)
            })
        defer { model.stop() }
        model.query = "why is the sky blue?"
        await model.waitForPendingResults()
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(model.items.first?.row.kind, .search)
        XCTAssertEqual(model.selectedResultIndex, 0)
        let card = try XCTUnwrap(model.items.first { $0.row.card?.kind == .generativeAnswer })
        XCTAssertEqual(card.row.card?.value, "Synthetic local answer")
        model.activate(card.row)
        XCTAssertEqual(copied, ["Synthetic local answer"])
        XCTAssertTrue(opened.isEmpty)
        model.query = "why are leaves green?"
        await model.waitForPendingResults()
        model.pressReturn()
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened[0].absoluteString.contains("why%20are%20leaves%20green"))
    }

    func testUnavailableAndRefusedAreNotCopyableAndNeverFallBackToRemote() async throws {
        for status: PaletteGenerativeStatus in [.intelligenceDisabled, .modelNotReady, .refused, .failed] {
            let model = try makeModel { lookup in PaletteGenerativeResult(lookup: lookup, text: nil, status: status) }
            model.query = "why is the sky blue?"
            await model.waitForPendingResults()
            XCTAssertEqual(model.generativeStatus, status)
            XCTAssertNil(model.items.first { $0.row.card?.kind == .generativeAnswer }?.row.card?.value)
            XCTAssertTrue(model.canRetryGenerativeAnswer)
            model.stop()
        }
    }

    func testDisabledAndLocalAnswersNeverReachGenerator() async throws {
        let model = try makeModel(enabled: false) { lookup in
            XCTFail("Disabled source must not invoke generator")
            return PaletteGenerativeResult(lookup: lookup, text: nil, status: .failed)
        }
        defer { model.stop() }
        model.query = "why is the sky blue?"
        await model.waitForPendingResults()
        XCTAssertFalse(model.items.contains { $0.row.card?.kind == .generativeAnswer })
    }

    func testExplicitPrivateButIneligiblePromptsNeverCallRemoteBoundariesEvenWhenSourceIsOff() async throws {
        for enabled in [false, true] {
            let remote = PrivateAnswerRemoteCalls()
            var available = true
            let model = try makeModel(
                enabled: enabled, isSourceAvailable: { _ in available }, remoteCalls: remote,
                generate: { lookup in
                    XCTFail("Ineligible text must not invoke the local model either")
                    return PaletteGenerativeResult(lookup: lookup, text: nil, status: .failed)
                })
            defer { model.stop() }
            // Positive controls prove both opted-in remote boundaries can run.
            model.query = "Ada Lovelace"
            await model.waitForPendingResults()
            let control = await remote.counts
            XCTAssertGreaterThan(control.suggestions, 0)
            XCTAssertGreaterThan(control.summaries, 0)
            await remote.reset()
            let privateText =
                [
                    "ask ode hi", "ask ode explain password protection", "ask ode what is example.com",
                    "ask ode ", "ask ode explain hunter2!x", "translate P@ssw0rd123 to French",
                    "translate hello to fre", "translate example.com to French", "translate", "how do you say",
                ]
                + (enabled
                    ? [
                        "ask", "ask o", "ask od", "why", "why is", "why is the",
                        "rewrite", "rephrase hi", "proofread:", "summarize hi", "shorten: hi",
                        "rewrite my password hunter2", "rephrase jane@example.test",
                    ] : [])
            for text in privateText {
                model.query = text
                await model.waitForPendingResults()
                XCTAssertFalse(model.items.contains { $0.row.card?.kind == .generativeAnswer })
                if enabled {
                    let original = model.browser.workspaceModel?.appPreferences ?? .default
                    var disabled = original
                    disabled.palette = disabled.palette.offering(.askOde, false)
                    try model.browser.core.send(
                        SetAppPreferences(workspaceID: model.browser.family.workspaceID, preferences: disabled))
                    model.preferencesChanged()
                    await model.waitForPendingResults()
                    available = false
                    model.sourceAvailabilityChanged(false)
                    available = true
                    model.sourceAvailabilityChanged(true)
                    await model.waitForPendingResults()
                    XCTAssertFalse(model.items.contains { $0.row.card?.kind == .generativeAnswer })
                    try model.browser.core.send(
                        SetAppPreferences(workspaceID: model.browser.family.workspaceID, preferences: original))
                    model.preferencesChanged()
                    await model.waitForPendingResults()
                }
            }
            let privateCalls = await remote.counts
            XCTAssertEqual(privateCalls.suggestions, 0)
            XCTAssertEqual(privateCalls.summaries, 0)
            // New ordinary text clears the private latch after source recovery.
            model.query = enabled ? "rewritten article" : "rewrite hi"
            await model.waitForPendingResults()
            let recovered = await remote.counts
            XCTAssertGreaterThan(recovered.suggestions, 0)
            XCTAssertGreaterThan(recovered.summaries, 0)
        }
    }

    // MARK: - Actions - Lifetime

    func testRapidTypingDebouncesAndOnlyNewestPendingPromptRunsAfterIgnoredCancellation() async throws {
        let started = expectation(description: "First generation")
        let gate = PrivateAnswerGate(started: started)
        let model = try makeModel(debounce: .milliseconds(30)) { await gate.answer($0) }
        defer { model.stop() }
        model.query = "why is the sky blue?"
        await fulfillment(of: [started], timeout: 2)
        for index in 0..<20 { model.query = "ask ode explain synthetic topic number \(index)" }
        // Let the newest idle pause expire while the old service ignores cancellation.
        try await Task.sleep(for: .milliseconds(100))
        let before = await gate.requests
        XCTAssertEqual(before.count, 1, "Never accumulate concurrent model work")
        await gate.finish()
        await model.waitForPendingResults()
        let requests = await gate.requests
        XCTAssertEqual(requests.map(\.text), ["why is the sky blue?", "explain synthetic topic number 19"])
        XCTAssertEqual(
            model.items.first { $0.row.card?.kind == .generativeAnswer }?.row.card?.value,
            "explain synthetic topic number 19")
    }

    func testMarkedTextAndCloseDropNoncooperativeOutputAndClearPrompt() async throws {
        for close in [false, true] {
            let started = expectation(description: "Generation")
            let gate = PrivateAnswerGate(started: started)
            let model = try makeModel { await gate.answer($0) }
            model.query = "why is the sky blue?"
            await fulfillment(of: [started], timeout: 2)
            if close {
                model.dismiss()
                model.stop()
            } else {
                model.updateCompletionEditing(text: "日本", selection: NSRange(location: 2, length: 0), isComposing: true)
                model.pressReturn()
            }
            await gate.finish()
            await model.waitForPendingResults()
            XCTAssertTrue(model.items.isEmpty)
            if close { XCTAssertTrue(model.query.isEmpty) }
            if !close {
                model.updateCompletionEditing(
                    text: "24 * 7", selection: NSRange(location: 6, length: 0), isComposing: false)
                await model.waitForPendingResults()
                XCTAssertEqual(model.items.first { $0.row.card != nil }?.row.card?.kind, .calculation)
            }
            model.stop()
        }
    }

    func testSourceLossOrPreferenceDisableRevokesPendingOutputAndSourceRecoveryWorks() async throws {
        for disable in [false, true] {
            let started = expectation(description: "Generation")
            let gate = PrivateAnswerGate(started: started)
            var available = true
            let model = try makeModel(
                isSourceAvailable: { _ in available }, generate: { await gate.answer($0) })
            defer { model.stop() }
            model.query = "why is the sky blue?"
            await fulfillment(of: [started], timeout: 2)
            if disable {
                var preferences = model.browser.workspaceModel?.appPreferences ?? .default
                preferences.palette = preferences.palette.offering(.askOde, false)
                try model.browser.core.send(
                    SetAppPreferences(workspaceID: model.browser.family.workspaceID, preferences: preferences))
                model.preferencesChanged()
            } else {
                available = false
                model.sourceAvailabilityChanged(false)
            }
            await gate.finish()
            await model.waitForPendingResults()
            XCTAssertFalse(model.items.contains { $0.row.card?.value == "why is the sky blue?" })
            if !disable {
                available = true
                model.sourceAvailabilityChanged(true)
                await model.waitForPendingResults()
                XCTAssertEqual(
                    model.items.first { $0.row.card?.kind == .generativeAnswer }?.row.card?.value,
                    "why is the sky blue?")
            }
        }
    }

    func testSourceRevocationDropsOutputEvenBeforeThePresentationObserverRuns() async throws {
        let started = expectation(description: "Generation")
        let gate = PrivateAnswerGate(started: started)
        var available = true
        let model = try makeModel(
            isSourceAvailable: { _ in available }, generate: { await gate.answer($0) })
        defer { model.stop() }
        model.query = "why is the sky blue?"
        await fulfillment(of: [started], timeout: 2)
        available = false
        await gate.finish()
        await model.waitForPendingResults()
        XCTAssertFalse(model.items.contains { $0.row.card?.value == "why is the sky blue?" })
    }

    func testLateAnswerPreservesSelectionIdentityAndKeyboardScrollRevision() async throws {
        let started = expectation(description: "Generation")
        let gate = PrivateAnswerGate(started: started)
        let model = try makeModel { await gate.answer($0) }
        defer { model.stop() }
        model.query = "why is the sky blue?"
        await fulfillment(of: [started], timeout: 2)
        model.moveSelection(by: 1)
        let selected = model.items[model.selectedResultIndex].id
        let revision = model.keyboardSelectionRevision
        await gate.finish()
        await model.waitForPendingResults()
        XCTAssertEqual(model.items[model.selectedResultIndex].id, selected)
        XCTAssertEqual(model.keyboardSelectionRevision, revision)
        XCTAssertEqual(model.items.first?.row.kind, .search)
    }

    // MARK: - Actions - Fixtures

    private func makeModel(
        enabled: Bool = true,
        commands: BrowserCommandPaletteCommandRegistry? = nil,
        debounce: Duration = .zero,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool = { _ in true },
        openURL: @escaping (URL) -> Bool = { _ in false },
        remoteCalls: PrivateAnswerRemoteCalls? = nil,
        generate: @escaping @Sendable (PaletteGenerativeLookup) async -> PaletteGenerativeResult
    ) throws -> BrowserCommandPaletteModel {
        let tab = TabState.Seed.startPage()
        var browsing = BrowsingPreferences.seeded
        browsing.followsDefaultSuggestions = false
        browsing.searchSuggestionsEnabled = true
        let space = SpaceState.Seed(
            name: "Private answer", symbol: "sparkles", accent: .indigo, folders: [], tabs: [tab],
            browsingPreferences: browsing)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        var preferences = AppPreferences.default
        preferences.palette.sources = preferences.palette.sources.map {
            PaletteSourceChoice(source: $0.source, isEnabled: $0.source == .askOde ? enabled : true, limit: $0.limit)
        }
        try browser.core.send(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: preferences))
        return BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: commands,
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: .zero,
                fetchSuggestions: { _ in
                    await remoteCalls?.recordSuggestion()
                    if enabled && remoteCalls == nil { XCTFail("Private prompt must never reach search suggestions") }
                    return []
                },
                lookUpDefinition: { _ in nil },
                fetchWebSummary: { _ in
                    await remoteCalls?.recordSummary()
                    if enabled && remoteCalls == nil { XCTFail("Private prompt must never reach web summaries") }
                    return nil
                },
                generativeDebounce: debounce, generateAnswer: generate),
            isSourceAvailable: isSourceAvailable, selectTab: { _, _ in false },
            openURL: { _, url, _ in openURL(url) }, dismiss: {})
    }
}

private actor PrivateAnswerRemoteCalls {
    // MARK: - Variables

    private(set) var counts = (suggestions: 0, summaries: 0)

    // MARK: - Actions - Recording

    func recordSuggestion() { counts.suggestions += 1 }
    func recordSummary() { counts.summaries += 1 }
    func reset() { counts = (0, 0) }
}

private actor PrivateAnswerGate {
    // MARK: - Variables

    private let started: XCTestExpectation
    private var pending: (PaletteGenerativeLookup, CheckedContinuation<PaletteGenerativeResult, Never>)?
    private(set) var requests: [PaletteGenerativeLookup] = []

    // MARK: - Initializers

    init(started: XCTestExpectation) { self.started = started }

    // MARK: - Actions - Generation

    func answer(_ lookup: PaletteGenerativeLookup) async -> PaletteGenerativeResult {
        requests.append(lookup)
        guard requests.count == 1 else {
            return PaletteGenerativeResult(lookup: lookup, text: lookup.text, status: .answered)
        }
        return await withCheckedContinuation { continuation in
            pending = (lookup, continuation)
            started.fulfill()
        }
    }

    func finish() {
        guard let pending else { return }
        self.pending = nil
        pending.1.resume(returning: PaletteGenerativeResult(lookup: pending.0, text: pending.0.text, status: .answered))
    }
}
