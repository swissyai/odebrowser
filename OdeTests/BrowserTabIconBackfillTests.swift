import Foundation
import XCTest

@testable import Ode

/// Kept tabs that no page loaded, such as an import's, wear the icon found
/// for their site, which the next launch still shows; a locked Space's tabs
/// are never looked up until it is unlocked.
@MainActor
final class BrowserTabIconBackfillTests: XCTestCase {
    func testKeptTabsWithoutIconsWearTheFoundIconAcrossLaunchesAndLockedSpacesWaitForUnlock() async throws {
        let pinned = TabState.Seed(
            title: "Pinned", url: URL(string: "https://pinned.example/inbox#top"), placement: .pinned)
        let saved = TabState.Seed(title: "Saved", url: URL(string: "https://saved.example/board"), placement: .saved)
        let local = TabState.Seed(title: "Router", url: URL(string: "http://192.168.1.1/"), placement: .saved)
        let secret = TabState.Seed(title: "Secret", url: URL(string: "https://secret.example/"), placement: .pinned)
        let open = SpaceState.Seed(name: "Open", tabs: [pinned, saved, local, .startPage()])
        let locked = SpaceState.Seed(
            name: "Locked", tabs: [secret, .startPage()], accessPolicy: .deviceOwnerAuthentication)
        let harness = try BrowserStoredSessionHarness(seed: SessionState.Seed(spaces: [open, locked]))
        let icon = SiteIconFixture.png(side: 64)
        let lookups = Lookups()
        // One lookup at a time, so the order work is handed out in is the
        // order the pages are asked for.
        let backfill = BrowserTabIconBackfill(
            state: harness.core.state, workspaceID: harness.store.family.workspaceID, concurrentLookups: 1,
            find: { page, _ in
                await lookups.record(page)
                return icon
            })

        backfill.start(after: .zero)
        try await waitUntil { harness.favicons.favicon(tabID: saved.id) != nil }

        XCTAssertEqual(harness.core.state.favicons.image(of: pinned.id), icon)
        XCTAssertEqual(harness.favicons.favicon(tabID: pinned.id), icon)
        var asked = await lookups.pages
        XCTAssertEqual(asked.map { $0.host() }, ["pinned.example", "saved.example"], "Pinned tabs are filled first")
        XCTAssertFalse(asked.contains { $0.host() == "secret.example" }, "A locked Space's sites are never asked")
        XCTAssertFalse(asked.contains { $0.host() == "192.168.1.1" }, "Local addresses are never asked")
        XCTAssertNil(harness.core.state.favicons.image(of: secret.id))

        harness.store.unlockForTesting(locked)
        try await waitUntil { harness.favicons.favicon(tabID: secret.id) != nil }
        asked = await lookups.pages
        XCTAssertEqual(
            asked.filter { $0.host() == "pinned.example" }.count, 1, "A tab that wears its icon is not asked again")

        let next = try await harness.relaunch()
        XCTAssertEqual(next.core.state.favicons.image(of: pinned.id), icon)
        XCTAssertEqual(next.core.state.favicons.image(of: secret.id), icon)
    }

    /// The pages looked up, in order.
    private actor Lookups {
        private(set) var pages: [URL] = []

        func record(_ page: URL) {
            pages.append(page)
        }
    }
}
