import Observation
import XCTest

@testable import Ode

@MainActor
final class BrowserSoftwareUpdateTests: XCTestCase {
    func testApplicationRequiresSignedSparkleUpdatesFromTheOfficialFeed() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://odebrowser.com/updates/appcast.xml"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "9aWsrqsUJlDCip5UPtCD6qwxF0ZUkGyjXdFO9VW2ikk="
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool,
            true
        )
        // Updates check, download and install by themselves unless the
        // person turns that off, so fixes reach people who never ask.
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval")
                as? Double,
            BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool,
            true
        )
        // The packaged default follows the branch (Experimental on a branch
        // build, Development or Stable on main); it must always name a
        // channel the app understands, or updates would fall back silently.
        XCTAssertNotNil(
            (Bundle.main.object(forInfoDictionaryKey: "OdeDefaultUpdateChannel") as? String)
                .flatMap(BrowserSoftwareUpdateChannel.named)
        )
    }

    func testReleaseChannelsMapToTheirSignedFeedsAndSparkleChannels() {
        XCTAssertEqual(BrowserSoftwareUpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.nightly.allowedSparkleChannels, ["nightly"])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.development.allowedSparkleChannels, ["development"])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.experimental.allowedSparkleChannels, ["experimental"])

        // Each product keeps its own feeds whichever engine this test host
        // runs: the dual-engine product reads the main feed from its
        // Info.plist, and WebKit-only installs follow the -webkit feeds.
        let feeds = "https://odebrowser.com/updates/"
        let expected: [(channel: BrowserSoftwareUpdateChannel, chromium: String?, webKit: String)] = [
            (.stable, nil, "appcast-webkit.xml"),
            (.nightly, nil, "appcast-webkit.xml"),
            (.development, "appcast-development.xml", "appcast-development-webkit.xml"),
            (.experimental, "appcast-experimental.xml", "appcast-experimental-webkit.xml"),
        ]
        for feed in expected {
            XCTAssertEqual(
                feed.channel.feedURL(for: .chromium)?.absoluteString,
                feed.chromium.map { feeds + $0 },
                feed.channel.name
            )
            XCTAssertEqual(feed.channel.feedURL(for: .webKit)?.absoluteString, feeds + feed.webKit, feed.channel.name)
        }
    }

    func testBundledChannelBecomesTheDefaultUntilTheUserChoosesAnother() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)

        service.channel = .nightly

        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.nightly.name
        )
    }

    func testInstallingAnArtifactFromAnotherChannelAdoptsItsBundledChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)
        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.development.name
        )
    }

    func testUserChoiceSurvivesRelaunchesOfTheSameArtifactChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.nightly.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.development.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .nightly)
    }

    /// The sidebar combines the existing automatic preferences without enabling idle restarts.
    /// Isolated fixtures exercise that same composition without changing Sparkle's persisted preferences.
    func testSidebarAutomaticUpdatesCombinesChecksAndDownloadsWithoutChangingIdleRestart() async {
        let service = BrowserSoftwareUpdateService(isEnabled: false, preferences: nil)
        service.presentIsolatedSidebarWidgetFixture("automatic-ready:0.8.99:899")
        let idleRestart = service.restartsWhenIdle
        service.setAutomaticallyChecksForUpdates(false)
        service.setAutomaticallyDownloadsUpdates(true)
        XCTAssertFalse(service.automaticUpdatesEnabled)

        service.setAutomaticUpdates(true)
        XCTAssertTrue(service.automaticallyChecksForUpdates)
        XCTAssertTrue(service.automaticallyDownloadsUpdates)
        XCTAssertTrue(service.automaticUpdatesEnabled)
        XCTAssertEqual(service.restartsWhenIdle, idleRestart)
        let changed = expectation(description: "The sidebar observes a change made through Settings")
        withObservationTracking {
            _ = service.automaticUpdatesEnabled
        } onChange: {
            changed.fulfill()
        }
        service.setAutomaticallyDownloadsUpdates(false)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertFalse(service.automaticUpdatesEnabled)

        service.setAutomaticUpdates(true)
        service.setAutomaticUpdates(false)
        XCTAssertTrue(service.automaticallyChecksForUpdates, "Manual update notifications keep their existing setting.")
        XCTAssertFalse(service.automaticallyDownloadsUpdates)
        XCTAssertFalse(service.automaticUpdatesEnabled)
        XCTAssertEqual(service.restartsWhenIdle, idleRestart)

        service.setAutomaticallyChecksForUpdates(false)
        service.setAutomaticUpdates(false)
        XCTAssertFalse(service.automaticallyChecksForUpdates, "Turning automatic downloads off must not enable checks.")
    }

    func testDownloadProgressAccumulatesAndClampsToTheExpectedLength() throws {
        let model = BrowserSoftwareUpdateModel()

        model.presentDownload(cancellation: {})
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(30)
        XCTAssertEqual(try XCTUnwrap(model.progress), 0.3, accuracy: 0.001)

        model.receiveDownloadedBytes(90)
        XCTAssertEqual(try XCTUnwrap(model.progress), 1, accuracy: 0.001)
    }

    func testSettledUpdateStatesDoNotRetainTransferProgress() throws {
        let model = BrowserSoftwareUpdateModel()
        model.presentDownload(cancellation: {})
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(42)
        XCTAssertEqual(try XCTUnwrap(model.snapshot.progress), 0.42, accuracy: 0.001)

        model.presentExtraction()
        model.setExtractionProgress(0.7)
        XCTAssertEqual(try XCTUnwrap(model.snapshot.progress), 0.7, accuracy: 0.001)
        model.presentReadyToInstall(install: {}, cancel: {})
        XCTAssertNil(model.snapshot.progress)
        XCTAssertTrue(model.snapshot.allowsInstallAndRelaunch)

        model.presentInstalled(relaunched: true, acknowledgement: {})
        XCTAssertNil(model.snapshot.progress)
        model.presentWhatsNew(version: "0.9.4", build: "1066", highlights: [], releaseNotes: "")
        XCTAssertNil(model.snapshot.progress)
        XCTAssertFalse(model.snapshot.allowsInstallAndRelaunch)
    }

    func testARelaunchOdeDidNotQuitForIsOfferedAgain() throws {
        let model = BrowserSoftwareUpdateModel()
        var relaunchRequests = 0
        model.presentAutomaticUpdateReady(
            title: "Ode 0.5.1",
            version: "0.5.1",
            build: "501",
            releaseNotes: nil,
            informationURL: nil,
            installAndRelaunch: { relaunchRequests += 1 }
        )

        model.installAndRelaunchNow()
        XCTAssertEqual(relaunchRequests, 1)
        XCTAssertEqual(model.phase, .installing)

        model.applicationStayedOpen()
        let snapshot = try XCTUnwrap(model.sidebarWidgetSnapshot)
        XCTAssertEqual(snapshot.phase, .readyToInstall)
        XCTAssertTrue(snapshot.allowsInstallAndRelaunch)

        model.installAndRelaunchNow()
        XCTAssertEqual(relaunchRequests, 2)
    }

    func testSidebarWidgetDismissesTheExactBuildAndAChangedBuildReappears() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])
        var skippedBuilds: [String] = []

        model.presentUpdate(
            title: "Ode 0.5.1",
            version: "0.5.1",
            build: "501",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("501") }
        )
        let firstEmission = await iterator.next()
        let first = try XCTUnwrap(firstEmission?.first)
        XCTAssertEqual(first.id.instanceID, "501")

        source.perform(.dismissExactUpdate, on: first.id)
        XCTAssertEqual(skippedBuilds, ["501"])
        let dismissed = await iterator.next()
        XCTAssertEqual(dismissed, [])

        model.presentUpdate(
            title: "Ode 0.5.2",
            version: "0.5.2",
            build: "502",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("502") }
        )
        let newerEmission = await iterator.next()
        let newer = try XCTUnwrap(newerEmission?.first)
        XCTAssertEqual(newer.id.instanceID, "502")
        XCTAssertNotEqual(newer.id, first.id)
    }

    // MARK: - What's new

    func testTheFirstLaunchAfterAnUpdateListsOnlyWhatChanged() throws {
        let suite = "BrowserSoftwareUpdateRollbackTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        func note(_ id: String, _ category: BrowserAboutReleaseNoteCategory) -> BrowserAboutReleaseNote {
            BrowserAboutReleaseNote(id: id, category: category, message: id)
        }
        let first = BrowserAboutReleaseNotes(entries: [note("2026-10-01-a", .new), note("2026-10-02-b", .internal)])
        XCTAssertNil(
            BrowserSoftwareUpdateWhatsNew.recordLaunch(
                preferences: preferences, ranBefore: false, version: "0.9.3", build: "100", catalog: first),
            "A first launch has nothing new to show")
        XCTAssertNil(
            BrowserSoftwareUpdateWhatsNew.recordLaunch(
                preferences: preferences, ranBefore: true, version: "0.9.3", build: "100", catalog: first))

        let second = BrowserAboutReleaseNotes(
            entries: first.entries + [note("2026-10-03-c", .fixed), note("2026-10-04-d", .internal)])
        let whatsNew = BrowserSoftwareUpdateWhatsNew.recordLaunch(
            preferences: preferences, ranBefore: true, version: "0.9.4", build: "200", catalog: second)
        XCTAssertEqual(whatsNew?.highlights, ["2026-10-03-c"], "Only the public changes the earlier build lacked")

        let recordedNothing = try XCTUnwrap(UserDefaults(suiteName: suite + ".earlier"))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite + ".earlier") }
        XCTAssertEqual(
            BrowserSoftwareUpdateWhatsNew.recordLaunch(
                preferences: recordedNothing, ranBefore: true, version: "0.9.4", build: "200", catalog: second)?
                .highlights,
            ["2026-10-03-c", "2026-10-01-a"],
            "After a build that recorded nothing, the newest changes")
    }
}
