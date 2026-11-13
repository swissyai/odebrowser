import Foundation
import XCTest

@testable import Ode

/// Shift-Return on a search opens its first result, as in Arc, where Return
/// would open the results; on a row that opens an address it keeps opening
/// Split View; offline it acts as Return; and the selected row says which.
@MainActor
final class BrowserCommandPaletteTopResultTests: XCTestCase {
    func testShiftReturnOnASearchOpensItsFirstResult() async throws {
        let (model, opened) = makeModel(online: true)
        model.query = "albert einstein"
        await model.waitForPendingResults()
        let search = try XCTUnwrap(model.items.first { $0.row.kind == .search }?.row)
        let topResult = try XCTUnwrap(search.topResult)
        XCTAssertTrue(topResult.hasPrefix("https://duckduckgo.com/?q=%5Calbert%20einstein"), topResult)
        XCTAssertEqual(model.shiftReturnOpening(for: search), .topResult)

        model.updateHeldModifiers([.shift])
        XCTAssertEqual(model.opening(for: search), .topResult)
        model.activate(search)

        XCTAssertEqual(opened.calls.map(\.url.absoluteString), [topResult])
        XCTAssertEqual(opened.calls.map(\.opening), [.topResult])
    }

    func testShiftReturnOnAnAddressKeepsOpeningSplitView() async throws {
        let (model, opened) = makeModel(online: true)
        model.query = "example.org"
        await model.waitForPendingResults()
        let address = try XCTUnwrap(model.items.first { $0.row.kind == .openAddress }?.row)
        XCTAssertNil(address.topResult)
        XCTAssertEqual(model.shiftReturnOpening(for: address), .splitView)

        model.updateHeldModifiers([.shift])
        model.activate(address)
        XCTAssertEqual(opened.calls.map(\.opening), [.splitView])
    }

    func testOfflineShiftReturnActsAsReturn() async throws {
        let (model, opened) = makeModel(online: false)
        model.query = "albert einstein"
        await model.waitForPendingResults()
        let search = try XCTUnwrap(model.items.first { $0.row.kind == .search }?.row)
        XCTAssertNil(model.shiftReturnOpening(for: search))

        model.updateHeldModifiers([.shift])
        model.activate(search)
        XCTAssertEqual(opened.calls.map(\.url.absoluteString), [search.address])
        XCTAssertEqual(opened.calls.map(\.opening), [.here])
    }

    // MARK: - Fixtures

    private final class Opened {
        var calls: [(url: URL, opening: BrowserCommandPaletteOpening)] = []
    }

    private func makeModel(online: Bool) -> (BrowserCommandPaletteModel, Opened) {
        let source = TabState.Seed.startPage(id: UUID(), lastActivatedAt: Date(timeIntervalSinceReferenceDate: 600))
        let space = SpaceState.Seed(
            id: UUID(), profileID: UUID(), name: "Top Result", symbol: "magnifyingglass", accent: .indigo, folders: [],
            tabs: [source])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: source.id])
        let opened = Opened()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: source.id, initialQuery: "",
            commands: nil,
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: .zero, fetchSuggestions: { _ in [] }, isOnline: { online }),
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in false },
            openURL: { _, url, opening in
                opened.calls.append((url, opening))
                return true
            },
            dismiss: {}, openings: BrowserCommandPaletteOpening.all)
        return (model, opened)
    }
}
