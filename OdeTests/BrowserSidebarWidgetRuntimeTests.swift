import Foundation
import XCTest

@testable import Ode

@MainActor
final class BrowserSidebarWidgetRuntimeTests: XCTestCase {
    func testRegistryOrdersKindsThenInstancesAndShowsEveryProfileTogether() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let profileID = UUID()
        let otherProfileID = UUID()
        let firstSpace = UUID()
        let secondSpace = UUID()
        let foreignSpace = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: firstSpace,
            profileID: profileID,
            ordinal: 2
        )
        let second = nowPlayingInstance(
            tabID: UUID(),
            spaceID: secondSpace,
            profileID: profileID,
            ordinal: 1
        )
        let foreign = nowPlayingInstance(
            tabID: UUID(),
            spaceID: foreignSpace,
            profileID: otherProfileID,
            ordinal: 0
        )
        let update = updateInstance(build: "599")

        let visible = registry.visibleInstances(
            from: [first, foreign, update, second],
            platform: .macOS,
            capabilities: [.persistentSidebar, .mediaSessions, .directSoftwareUpdates]
        )

        XCTAssertEqual(
            visible.map(\.id),
            [update.id, foreign.id, second.id, first.id],
            "Kind order first, then insertion ordinal, with no profile filtering."
        )
        XCTAssertEqual(
            visible.compactMap { instance -> UUID? in
                guard case .nowPlaying(let session) = instance.presentation
                else { return nil }
                return session.owner.spaceID
            },
            [foreignSpace, secondSpace, firstSpace],
            "The deck is one global layer: neither the active Space nor the active profile is part of visibility."
        )
    }

    func testRegistryFiltersPlatformCapabilitiesAndSingleInstanceKinds() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let updates = [updateInstance(build: "1"), updateInstance(build: "2")]

        XCTAssertTrue(
            registry.visibleInstances(
                from: updates,
                platform: .mobile,
                capabilities: [.persistentSidebar, .mediaSessions]
            ).isEmpty,
            "Mobile/App Store surfaces must not expose direct-distribution controls."
        )
        XCTAssertEqual(
            registry.visibleInstances(
                from: updates,
                platform: .macOS,
                capabilities: [.directSoftwareUpdates]
            ).count,
            1,
            "A single-instance registration cannot produce duplicate rows."
        )
    }

    func testRuntimePublishesEveryProfilesWidgetsToOneGlobalDeck() async throws {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let home = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: UUID(),
            ordinal: 1
        )
        let work = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: UUID(),
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        source.send([home, work])
        try await waitForVisibleInstanceIDs([home.id, work.id], in: runtime)

        XCTAssertEqual(
            runtime.instances(capabilities: [.mediaSessions]).map(\.id),
            [home.id, work.id],
            "Switching to a Space in another profile never removes the widget layer."
        )
    }

    func testCarouselSelectsNewestInstanceThenPreservesManualChoiceAcrossSpaces() async throws {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 1
        )
        let newest = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        source.send([first])
        try await waitForVisibleInstanceIDs([first.id], in: runtime)
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([first, newest])
        try await waitForVisibleInstanceIDs([first.id, newest.id], in: runtime)
        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            newest.id,
            "A newly registered widget becomes the centered carousel card."
        )

        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            first.id,
            "One global selection: it does not reset merely because its owner belongs to another Space or profile."
        )
    }

    func testCarouselSelectionPrunesRemovedWidgetsAndFallsBackToARemainingCard() async throws {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: UUID(),
            spaceID: UUID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: UUID(), capabilities: [.mediaSessions])
        source.send([first, second])
        try await waitForVisibleInstanceIDs([first.id, second.id], in: runtime)
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([second])
        try await waitForVisibleInstanceIDs([second.id], in: runtime)
        XCTAssertNil(
            runtime.carouselSelection,
            "Navigation or tab cleanup removes carousel state for the stale widget identity."
        )

        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            second.id,
            "Losing the centered card falls back to a widget that is still visible."
        )
    }

    private func nowPlayingInstance(
        tabID: UUID,
        spaceID: UUID,
        profileID: UUID,
        ordinal: UInt64
    ) -> BrowserSidebarWidgetInstance {
        let sessionID = BrowserMediaSessionID(
            tabID: tabID,
            documentIdentifier: "document-\(ordinal)"
        )
        let snapshot = BrowserMediaSessionSnapshot(
            id: sessionID,
            owner: BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            ),
            ownerTitle: "Owner Tab \(ordinal)",
            title: "Track \(ordinal)",
            artist: nil,
            album: nil,
            artworkData: nil,
            playbackState: .playing,
            isAudible: true,
            isMuted: false,
            availableActions: [.pause],
            orderingOrdinal: ordinal
        )
        return BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .nowPlaying,
                instanceID: sessionID.id
            ),
            scope: .profile(profileID),
            orderingOrdinal: ordinal,
            presentation: .nowPlaying(snapshot),
            availableActions: [.activateOwner, .pause]
        )
    }

    private func updateInstance(build: String) -> BrowserSidebarWidgetInstance {
        BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .softwareUpdate,
                instanceID: build
            ),
            scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(
                BrowserSoftwareUpdateWidgetSnapshot(
                    phase: .available,
                    title: "Ode Update",
                    version: "0.5.0",
                    build: build,
                    releaseNotes: nil,
                    informationURL: nil,
                    message: nil,
                    progress: nil,
                    isInformationOnly: false,
                    allowsInstallation: true,
                    allowsSkipping: true,
                    allowsCancellation: false,
                    allowsInstallAndRelaunch: false,
                    allowsInstallationRetry: false,
                    isFixture: true
                )
            ),
            availableActions: [.installUpdate, .dismissExactUpdate]
        )
    }

    private func waitForVisibleInstanceIDs(
        _ expectedIDs: [BrowserSidebarWidgetID],
        in runtime: BrowserSidebarWidgetRuntime,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while runtime.instances(capabilities: [.mediaSessions]).map(\.id) != expectedIDs {
            guard ContinuousClock.now < deadline else {
                XCTFail(
                    "Timed out waiting for the widget stream to publish the expected visible IDs.",
                    file: file,
                    line: line
                )
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class FakeSidebarWidgetSource: BrowserSidebarWidgetEventSource {
    let kindID: BrowserSidebarWidgetKindID
    private(set) var subscriptionCount = 0
    private(set) var terminationCount = 0
    private var current: [BrowserSidebarWidgetInstance] = []
    private var continuations: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]

    init(kindID: BrowserSidebarWidgetKindID) {
        self.kindID = kindID
    }

    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]> {
        subscriptionCount += 1
        let id = UUID()
        let (stream, continuation) = AsyncStream<[BrowserSidebarWidgetInstance]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                continuations[id] = nil
                terminationCount += 1
            }
        }
        continuation.yield(current)
        return stream
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {}

    func send(_ instances: [BrowserSidebarWidgetInstance]) {
        current = instances
        for continuation in continuations.values {
            continuation.yield(instances)
        }
    }
}
