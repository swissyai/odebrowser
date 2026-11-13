import XCTest

@testable import Ode

/// Back to Tab: which window shows a player's tab, whether that window comes
/// forward or the Space unlocks first, which player the menu goes to, and
/// where playback stands for the player's progress line.
@MainActor
final class BrowserMediaReturnRouteTests: XCTestCase {
    private let owner = BrowserTabRuntimeAssignment(tabID: UUID(), spaceID: UUID(), profileID: UUID())
    private let here = UUID()
    private let other = UUID()

    // MARK: - Routes

    func testReturnStaysInTheWindowThePersonIsIn() throws {
        let route = try XCTUnwrap(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: here,
                windows: [window(other, showsSpace: true), window(here)], isSpaceLocked: false))

        XCTAssertEqual(route.windowID, here, "The person's own window switches Space rather than another.")
        XCTAssertEqual(route.spaceID, owner.spaceID)
        XCTAssertEqual(route.tabID, owner.tabID)
        XCTAssertFalse(route.bringsWindowForward)
        XCTAssertFalse(route.unlocksSpace)
    }

    func testTheWindowShowingTheTabComesForward() throws {
        let route = try XCTUnwrap(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: here,
                windows: [window(here), window(other, presentsTab: true)], isSpaceLocked: false))

        XCTAssertEqual(route.windowID, other)
        XCTAssertTrue(route.bringsWindowForward)
    }

    func testAWindowWithoutTheTabHandsReturnToOneShowingItsSpace() throws {
        let third = UUID()
        let route = try XCTUnwrap(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: here,
                windows: [window(here, holdsTab: false), window(other), window(third, showsSpace: true)],
                isSpaceLocked: false))

        XCTAssertEqual(route.windowID, third, "A torn-off tab's window cannot show the person's own tabs.")
        XCTAssertTrue(route.bringsWindowForward)
    }

    func testWithNoWindowInFrontTheFirstThatHoldsTheTabShowsIt() throws {
        let route = try XCTUnwrap(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: nil,
                windows: [window(here, holdsTab: false), window(other)], isSpaceLocked: false))

        XCTAssertEqual(route.windowID, other)
        XCTAssertTrue(route.bringsWindowForward)
    }

    func testALockedSpaceUnlocksBeforeItsTabShows() throws {
        let route = try XCTUnwrap(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: here, windows: [window(here)], isSpaceLocked: true))

        XCTAssertTrue(route.unlocksSpace)
    }

    func testNoRouteWhenNoOpenWindowHoldsTheTab() {
        XCTAssertNil(
            BrowserMediaReturnRoute.resolve(
                owner: owner, fromWindow: here, windows: [window(here, holdsTab: false)], isSpaceLocked: false))
        XCTAssertNil(
            BrowserMediaReturnRoute.resolve(owner: owner, fromWindow: here, windows: [], isSpaceLocked: false))
    }

    // MARK: - Menu target

    func testBackToPlayingTabGoesToTheNewestPlayerThatPlays() {
        let older = session(ordinal: 1, playback: .playing)
        let newerPaused = session(ordinal: 3, playback: .paused)
        let newer = session(ordinal: 2, playback: .playing)

        XCTAssertEqual(BrowserMediaReturnRoute.target(in: [older, newerPaused, newer])?.id, newer.id)
        XCTAssertEqual(
            BrowserMediaReturnRoute.target(in: [session(ordinal: 1, playback: .paused), newerPaused])?.id,
            newerPaused.id, "With nothing playing, the newest paused player is still one to go back to.")
        XCTAssertNil(BrowserMediaReturnRoute.target(in: []))
    }

    // MARK: - Deck

    func testTheDeckLeavesOutPlayersWhoseTabTheWindowShows() {
        let shown = session(ordinal: 1, playback: .playing)
        let away = session(ordinal: 2, playback: .playing)
        let update = BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(kindID: .softwareUpdate, instanceID: "build"), scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(
                BrowserSoftwareUpdateWidgetSnapshot(
                    phase: .available, title: "Update", version: nil, build: nil, releaseNotes: nil,
                    informationURL: nil, message: nil, progress: nil, isInformationOnly: false,
                    allowsInstallation: true, allowsSkipping: false, allowsCancellation: false,
                    allowsInstallAndRelaunch: false, allowsInstallationRetry: false, isFixture: true)),
            availableActions: [])
        let instances = [update, instance(shown), instance(away)]

        let deck = BrowserSidebarWidgetHost.deckInstances(instances) { $0 == shown.owner }

        XCTAssertEqual(deck.map(\.id), [update.id, instance(away).id])
        XCTAssertEqual(BrowserSidebarWidgetHost.deckInstances(instances) { _ in false }.count, 3)
    }

    // MARK: - Source line

    func testTheLineUnderTheTitleNamesWhereItPlaysWithoutRepeatingIt() {
        func line(title: String?, artist: String? = nil, tab: String?) -> String? {
            BrowserMediaSessionSnapshot(
                id: BrowserMediaSessionID(tabID: owner.tabID, documentIdentifier: "document"), owner: owner,
                ownerTitle: tab, title: title, artist: artist, album: nil, artworkData: nil, playbackState: .playing,
                isAudible: true, isMuted: false, availableActions: [], orderingOrdinal: 1
            ).sourceLine
        }

        XCTAssertEqual(
            line(title: "Evening Set", artist: "Field Recordings", tab: "Evening Set - Radio"), "Field Recordings")
        XCTAssertEqual(line(title: "Evening Set", tab: "Evening Set - Radio"), "Radio")
        XCTAssertEqual(line(title: "Evening Set", tab: "Radio | Evening Set"), "Radio")
        XCTAssertEqual(line(title: "Evening Set", tab: "Live Radio"), "Live Radio")
        XCTAssertNil(line(title: "Evening Set", tab: "Evening Set"))
        XCTAssertNil(line(title: nil, tab: "Evening Set - Radio"), "The tab's name is already the title.")
    }

    // MARK: - Position

    func testPositionMovesOnAtItsRateAndStopsAtTheEnd() throws {
        let reported = Date(timeIntervalSinceReferenceDate: 1_000)
        let playing = try XCTUnwrap(
            BrowserMediaSessionPosition.decode(["elapsed": 30, "duration": 120, "rate": 1.5], at: reported))

        XCTAssertEqual(playing.elapsed(at: reported.addingTimeInterval(10)), 45)
        XCTAssertEqual(playing.fraction(at: reported.addingTimeInterval(10)), 0.375)
        XCTAssertEqual(playing.elapsed(at: reported.addingTimeInterval(1_000)), 120)
        XCTAssertEqual(playing.elapsed(at: reported.addingTimeInterval(-10)), 30, "A clock going back holds still.")

        let paused = try XCTUnwrap(
            BrowserMediaSessionPosition.decode(["elapsed": 30, "duration": 120, "rate": 0], at: reported))
        XCTAssertEqual(paused.elapsed(at: reported.addingTimeInterval(60)), 30)

        let clamped = try XCTUnwrap(
            BrowserMediaSessionPosition.decode(["elapsed": 500, "duration": 120, "rate": 1], at: reported))
        XCTAssertEqual(clamped.elapsed, 120)
    }

    func testLiveMissingOrMalformedPositionsShowNoProgress() {
        let date = Date()
        for value: Any? in [
            nil, "position", ["elapsed": 1, "rate": 1], ["elapsed": 1, "duration": 0, "rate": 1],
            ["elapsed": 1, "duration": Double.infinity, "rate": 1],
            ["elapsed": 1, "duration": 30 * 24 * 60 * 60, "rate": 1],
            ["elapsed": 1, "duration": 60, "rate": -1], ["elapsed": 1, "duration": 60, "rate": 100],
            ["elapsed": Double.nan, "duration": 60, "rate": 1],
        ] as [Any?] {
            XCTAssertNil(BrowserMediaSessionPosition.decode(value, at: date), "\(String(describing: value))")
        }
    }

    func testThePageMessageCarriesItsPositionToTheSession() throws {
        let reported = Date(timeIntervalSinceReferenceDate: 2_000)
        let event = try XCTUnwrap(
            BrowserMediaSessionPageEventDecoder.decode(
                [
                    "version": 1, "documentIdentifier": "document", "sequence": 1,
                    "location": "https://fixture.invalid/media", "active": true, "playbackState": "playing",
                    "actions": ["play", "pause"], "position": ["elapsed": 12, "duration": 240, "rate": 1],
                ], at: reported))
        XCTAssertEqual(
            event.position, BrowserMediaSessionPosition(elapsed: 12, duration: 240, rate: 1, reportedAt: reported))

        let store = BrowserMediaSessionStore()
        let endpoint = SilentMediaEndpoint()
        store.receive(event, owner: owner, fallbackTitle: nil, endpoint: endpoint)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.position, event.position)
    }

    // MARK: - Fixtures

    private func window(
        _ id: UUID, holdsTab: Bool = true, presentsTab: Bool = false, showsSpace: Bool = false
    ) -> BrowserMediaReturnRoute.Window {
        BrowserMediaReturnRoute.Window(id: id, holdsTab: holdsTab, presentsTab: presentsTab, showsSpace: showsSpace)
    }

    private func session(
        ordinal: UInt64, playback: BrowserMediaSessionPlaybackState
    ) -> BrowserMediaSessionSnapshot {
        let owner = BrowserTabRuntimeAssignment(tabID: UUID(), spaceID: UUID(), profileID: UUID())
        return BrowserMediaSessionSnapshot(
            id: BrowserMediaSessionID(tabID: owner.tabID, documentIdentifier: "document-\(ordinal)"),
            owner: owner, ownerTitle: "Tab \(ordinal)", title: "Track \(ordinal)", artist: nil, album: nil,
            artworkData: nil, playbackState: playback, isAudible: playback == .playing, isMuted: false,
            availableActions: [.play, .pause], orderingOrdinal: ordinal)
    }

    private func instance(_ session: BrowserMediaSessionSnapshot) -> BrowserSidebarWidgetInstance {
        BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(kindID: .nowPlaying, instanceID: session.id.id),
            scope: .profile(session.owner.profileID), orderingOrdinal: session.orderingOrdinal,
            presentation: .nowPlaying(session), availableActions: [.activateOwner])
    }
}

@MainActor
private final class SilentMediaEndpoint: BrowserMediaSessionCommandEndpoint {
    func performMediaSessionAction(_ action: MediaSessionAction, documentIdentifier: String) {}
    func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {}
}
