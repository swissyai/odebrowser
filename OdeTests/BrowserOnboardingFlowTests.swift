import AppKit
import Dispatch
import SQLite3
import XCTest

@testable import Ode

@MainActor
final class BrowserOnboardingFlowTests: XCTestCase {
    func testConfirmedOnboardingLayoutUpdatesTheRendererOwnerAndSurvivesItsSave() {
        let suite = "ode-onboarding-layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        var continued = 0
        let page = BrowserOnboardingLayoutPage(
            back: BrowserOnboardingBackAction(closes: false, action: {}), continueSetup: { continued += 1 },
            appearance: appearance, defaults: defaults)
        XCTAssertFalse(appearance.sidebarOnRight)

        page.confirmSelection(.right)

        XCTAssertTrue(appearance.sidebarOnRight)
        XCTAssertTrue(BrowserChromeAppearance.device(appearance, windowCornerRadius: nil).sidebarOnRight)
        appearance.saveNow()
        XCTAssertTrue(defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey))
        XCTAssertTrue(BrowserDeviceAppearanceStore(defaults: defaults).sidebarOnRight)
        page.confirmSelection(.top)
        XCTAssertTrue(appearance.sidebarOnRight, "Choosing top tabs preserves the next sidebar's side")
        page.confirmSelection(.left)
        XCTAssertFalse(appearance.sidebarOnRight)
        XCTAssertEqual(continued, 3)
    }

    func testContinuingWithoutImportingPreservesLookAndLayoutWithoutApplyingASelectedOrReviewedImport() async throws {
        let defaults = BrowserChromeAppearancePreference.defaults
        let keys = [
            BrowserChromeAppearancePreference.tabLayoutKey, BrowserChromeAppearancePreference.sidebarOnRightKey,
        ]
        let before = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, before) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(BrowserTabLayout.top.name, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        for preparesReview in [false, true] {
            let reader = SequencedImportReader(
                results: [.success(readOutput(application: .arc, spaces: [makeSpace(name: "Not Imported")]))])
            let flow = makeFlow(
                sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]), reader: reader, entryPoint: .firstRun)
            flow.start()
            flow.chooseLook(.heraldic)
            flow.show(.importBrowser)
            flow.discoverInstalledSources()
            let originalIDs = flow.browser.spaceModels.map(\.id)
            let originalTabs = flow.browser.spaceModels.flatMap { $0.tabs.values }
            if preparesReview {
                flow.continueImportQueue()
                try await waitUntil(interval: .zero) { flow.step == .review }
            }

            flow.beginManualSetup()

            XCTAssertEqual(flow.step, .manualSetup)
            XCTAssertEqual(flow.look, .heraldic)
            let result = await BrowserSetupFinish.finish(
                browser: flow.browser, spaceAccess: BrowserSpaceAccessController())
            XCTAssertTrue(result is BrowserSetupCompleted)
            XCTAssertEqual(flow.browser.spaceModels.map(\.id), originalIDs)
            XCTAssertEqual(flow.browser.spaceModels.flatMap { $0.tabs.values }, originalTabs)
            XCTAssertFalse(flow.browser.spaceModels.contains { $0.settings.name == "Not Imported" })
            XCTAssertEqual(defaults.string(forKey: keys[0]), BrowserTabLayout.top.name)
            XCTAssertTrue(defaults.bool(forKey: keys[1]))
            let reads = await reader.readCount
            XCTAssertEqual(reads, preparesReview ? 1 : 0)
        }
    }

    func testContinuingWithoutImportingDiscardsALateReadAndFinishesTheManualSetup() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]), reader: reader, entryPoint: .firstRun)
        flow.start()
        flow.chooseLook(.heraldic)
        flow.show(.importBrowser)
        flow.discoverInstalledSources()
        let originalIDs = flow.browser.spaceModels.map(\.id)
        let originalTabs = flow.browser.spaceModels.flatMap { $0.tabs.values }
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        flow.beginManualSetup()
        let discarded = expectation(description: "Continuing without import discards the abandoned read")
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Not Imported")])
        output.discard = { discarded.fulfill() }
        await reader.complete(output)
        await fulfillment(of: [discarded], timeout: 2)

        XCTAssertEqual(flow.step, .manualSetup)
        XCTAssertEqual(flow.look, .heraldic)
        XCTAssertNil(flow.review)
        let result = await BrowserSetupFinish.finish(browser: flow.browser, spaceAccess: BrowserSpaceAccessController())
        XCTAssertTrue(result is BrowserSetupCompleted)
        XCTAssertEqual(flow.browser.spaceModels.map(\.id), originalIDs)
        XCTAssertEqual(flow.browser.spaceModels.flatMap { $0.tabs.values }, originalTabs)
    }

    func testAFailedReadRetriesAndTheReviewedImportLandsInTheSession() async throws {
        let reader = SequencedImportReader(
            results: [
                .failure(TestFailure.read),
                .success(readOutput(application: .safari, spaces: [makeSpace(name: "Imported")])),
            ]
        )
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]), reader: reader)
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)

        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.failure != nil }
        XCTAssertEqual(flow.step, .importBrowser)
        XCTAssertEqual(flow.failure?.message, .verbatim(TestFailure.read.localizedDescription))
        XCTAssertEqual(flow.selectedImportApplications, [.safari])

        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        XCTAssertNil(flow.failure)
        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 2)

        flow.commitReviewedImport()
        try await waitUntil(interval: .zero) { flow.step == .complete }
        XCTAssertEqual(flow.browser.spaceModels.filter { $0.settings.name == "Imported" }.count, 1)
    }

    /// Import choices and later draft edits have distinct commit boundaries.
    /// Going Back, resuming the held draft and leaving practice must not
    /// replace imported tabs or apply customization before Finish. A new Mac
    /// setup request deliberately starts its transient draft over.
    func testImportedSpacesSurviveDraftNavigationResumeAndPracticeCleanup() async throws {
        let work = SpaceState.Seed(
            name: "Imported Work", accent: .indigo,
            tabs: [
                TabState.Seed(title: "Keep", url: URL(string: "https://work.example/keep"), placement: .saved),
                TabState.Seed(title: "Leave", url: URL(string: "https://work.example/leave"), placement: .current),
            ])
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: SequencedImportReader(
                results: [.success(readOutput(application: .safari, spaces: [work, makeSpace(name: "Imported Home")]))]
            ),
            entryPoint: .firstRun)
        flow.start()
        flow.show(.importBrowser)
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let reviewed = try XCTUnwrap(flow.reviewSpaces.first { $0.sourceSpace.settings.name == "Imported Work" })
        let leftOut = try XCTUnwrap(reviewed.sourceSpace.tabs.models.first { $0.title == "Leave" })
        flow.setIncluded(leftOut.id, false, in: reviewed.id)
        flow.commitReviewedImport()
        try await waitUntil(interval: .zero) { flow.step == .manualSetup }

        let imported = flow.browser.sessionSeed
        let actual = try XCTUnwrap(flow.destinationSpaces.first { $0.settings.name == "Imported Work" })
        XCTAssertEqual(actual.tabs.models.map(\.title), ["Keep"])
        let home = try XCTUnwrap(flow.destinationSpaces.first { $0.settings.name == "Imported Home" })
        XCTAssertNotEqual(actual.id, home.id)
        let importedTabs = actual.tabs.values
        let unchangedHome = home.value
        let setup = flow.manualSetup
        setup.nameBinding(for: actual.id).wrappedValue = "My Work"
        setup.symbolBinding(for: actual.id).wrappedValue = "briefcase.fill"
        setup.brandingBinding(for: actual.id).wrappedValue = SpaceColorPreset.azure.branding
        let draft = try XCTUnwrap(setup.space(actual.id))
        flow.show(.practice)
        flow.show(.manualSetup)
        flow.cancelOperations()
        flow.beginManualSetup()
        XCTAssertEqual(setup.space(actual.id), draft)
        XCTAssertEqual(flow.browser.sessionSeed, imported)

        flow.reset(for: BrowserOnboardingRequest(entryPoint: .firstRun))
        flow.beginManualSetup()
        XCTAssertEqual(setup.space(actual.id)?.customization.name, actual.settings.name)
        XCTAssertEqual(flow.browser.sessionSeed, imported)
        setup.nameBinding(for: actual.id).wrappedValue = draft.customization.name
        setup.symbolBinding(for: actual.id).wrappedValue = draft.customization.symbol
        setup.brandingBinding(for: actual.id).wrappedValue = draft.customization.branding
        XCTAssertEqual(setup.space(actual.id), draft)

        let practice = try BrowserOnboardingPractice(shortcuts: BrowserShortcutStore(core: flow.browser.core))
        defer { practice.leave() }
        practice.browser.selectTab(practice.sampleID)
        practice.actions.perform(.nextSpace)
        practice.leave()
        XCTAssertFalse(practice.browser.family.isOpen)
        XCTAssertEqual(flow.browser.sessionSeed, imported)
        flow.show(.practice)
        let result = await BrowserSetupFinish.finish(browser: flow.browser, spaceAccess: BrowserSpaceAccessController())
        XCTAssertTrue(result is BrowserSetupCompleted)
        let finished = try XCTUnwrap(flow.browser.spaceModel(actual.id))
        XCTAssertEqual(finished.settings.name, "My Work")
        XCTAssertEqual(finished.settings.symbol, draft.customization.symbol)
        XCTAssertEqual(finished.settings.look, draft.customization.branding)
        XCTAssertEqual(finished.tabs.values, importedTabs)
        XCTAssertEqual(flow.browser.spaceModel(home.id)?.value, unchangedHome)
        XCTAssertNil(setup.draft)
    }

    /// The icons the browser kept for the pages its tabs show come with the
    /// import: the review shows them and each tab the import brings wears its
    /// own, whether its page was loaded or not.
    func testTheTabsAnImportBringsWearTheIconsTheBrowserKept() async throws {
        let pinned = TabState.Seed(title: "Mail", url: URL(string: "https://mail.example/inbox"), placement: .pinned)
        let current = TabState.Seed(title: "Plain", url: URL(string: "https://plain.example/"), placement: .current)
        var output = readOutput(
            application: .chrome,
            spaces: [SpaceState.Seed(name: "With Icons", accent: .indigo, tabs: [pinned, current])])
        let icon = SiteIconFixture.png(side: 64)
        output.siteIcons = ["https://mail.example/inbox": icon]
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: SequencedImportReader(results: [.success(output)]))
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let review = try XCTUnwrap(flow.reviewSpaces.first)
        let previewTabs = try XCTUnwrap(flow.previewDestinationSpace(for: review)).tabs.models
        XCTAssertEqual(
            previewTabs.compactMap { flow.previewFavicons.image(of: $0.id) }, [icon],
            "The review shows the icon the browser kept")

        flow.commitReviewedImport()
        try await waitUntil(interval: .zero) { flow.step == .complete }
        let space = try XCTUnwrap(flow.browser.spaceModels.first { $0.settings.name == "With Icons" })
        let mail = try XCTUnwrap(space.tabs.models.first { $0.url == "https://mail.example/inbox" })
        let plain = try XCTUnwrap(space.tabs.models.first { $0.url == "https://plain.example/" })
        XCTAssertEqual(flow.browser.core.state.favicons.image(of: mail.id), icon)
        XCTAssertNil(flow.browser.core.state.favicons.image(of: plain.id))
    }

    /// Setup reads no browser's data until the person asks: opening it lists
    /// the browsers by their apps, and going on with one reads that one alone.
    func testSetupReadsOnlyTheBrowserThePersonGoesOnWith() async throws {
        let discovery = RecordingSourceDiscovery(read: [source(.chrome), source(.arc)])
        let flow = makeFlow(
            sourceDiscovery: discovery,
            reader: SequencedImportReader(
                results: [.success(readOutput(application: .chrome, spaces: [makeSpace(name: "Chrome")]))]))
        flow.start()
        flow.discoverInstalledSources()
        XCTAssertEqual(flow.offeredSources.map(\.application), [.chrome, .arc])
        XCTAssertTrue(discovery.readApplications.isEmpty)

        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        XCTAssertEqual(discovery.readApplications, [.chrome])
    }

    func testCancellationPreventsALateReadFromPublishingAReview() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]), reader: reader)
        flow.start()
        flow.discoverInstalledSources()
        // Arc comes chosen.
        XCTAssertEqual(flow.selectedImportApplications, [.arc])
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        flow.cancelImportRead()
        let discarded = expectation(description: "The cancelled read releases its late result")
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Too Late")])
        output.discard = { discarded.fulfill() }
        await reader.complete(output)
        await fulfillment(of: [discarded], timeout: 2)

        XCTAssertEqual(flow.step, .importBrowser)
        XCTAssertEqual(flow.state?.phase, .idle)
        XCTAssertNil(flow.review)
        XCTAssertNil(flow.failure)
    }

    func testSkippingAReadEndsSetupNormallyAndALateReadCannotTouchExistingData() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]), reader: reader)
        let original = flow.browser.sessionSeed
        flow.start()
        flow.discoverInstalledSources()
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        XCTAssertTrue(flow.prepareToSkipToEnd())
        let result = await BrowserSetupFinish.finish(
            browser: flow.browser, spaceAccess: BrowserSpaceAccessController(), skipping: true)
        XCTAssertTrue(result is BrowserSetupCompleted)
        XCTAssertEqual(flow.browser.core.state.setupCompleted, true)
        let discarded = expectation(description: "Skipping setup releases the abandoned import result")
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Not Imported")])
        output.discard = { discarded.fulfill() }
        await reader.complete(output)
        await fulfillment(of: [discarded], timeout: 2)
        XCTAssertEqual(flow.browser.sessionSeed, original)
        XCTAssertNil(flow.review)
    }

    /// An import that has begun applying finishes, whatever the window does
    /// meanwhile; the reset it held back runs after it.
    func testResetDuringFinalizationLetsTheCommittedImportFinish() async throws {
        let committer = PostMutationSuspendedImportCommitter()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: SequencedImportReader(
                results: [
                    .success(readOutput(application: .safari, spaces: [makeSpace(name: "Committed Before Reset")]))
                ]),
            importCommitter: committer
        )
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        flow.commitReviewedImport()
        await committer.waitUntilFinalizationStarted()
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Committed Before Reset" })

        flow.reset(for: BrowserOnboardingRequest(entryPoint: .manualSetup))
        XCTAssertTrue(flow.isCommittingImport)
        XCTAssertFalse(flow.prepareToSkipToEnd(), "Skipping cannot interrupt a committed import")

        committer.completeFinalization()
        try await waitUntil(interval: .zero) { !flow.isCommittingImport && flow.step == .manualSetup }
        XCTAssertNil(flow.failure)
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Committed Before Reset" })
        XCTAssertEqual(flow.importOutcomes.map(\.status), [.imported])
    }

    /// An import that will ask macOS for the browser's key explains why
    /// first, imports nothing until the person goes on, and can go on
    /// without passwords, which asks for nothing.
    func testAnImportThatAsksForTheKeychainExplainsFirstAndCanLeaveOutSecrets() async throws {
        var output = readOutput(application: .chrome, spaces: [makeSpace(name: "Personal")])
        output = BrowserOnboardingImportReadOutput(
            payload: output.payload, imported: output.imported,
            passwordCandidates: [
                BrowserPasswordImportCandidate(
                    sourceApplication: .chrome, sourceProfileID: "Default", sourceProfileName: "Personal",
                    origin: try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))))
            ])
        let secret = FixtureImportSafeStorage()
        let committer = LiveBrowserOnboardingImportCommitter(safeStorage: secret)
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: SequencedImportReader(results: [.success(output)]),
            importCommitter: committer)
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let review = try XCTUnwrap(flow.review)
        XCTAssertGreaterThan(review.includedPasswordCount, 0)
        XCTAssertTrue(flow.asksForKeychainKey(review))

        flow.commitReviewedImport()
        XCTAssertTrue(flow.isExplainingKeychain)
        XCTAssertFalse(flow.isCommittingImport)
        XCTAssertEqual(secret.readCount, 0)

        flow.importWithoutSecrets()
        try await waitUntil(interval: .zero) { flow.step == .complete }
        XCTAssertFalse(flow.isExplainingKeychain)
        XCTAssertEqual(secret.readCount, 0)
        XCTAssertEqual(flow.review?.includedPasswordCount ?? 0, 0)
        XCTAssertEqual(flow.importOutcomes.last?.passwordCount, 0)
    }

    /// A password failure leaves the review with everything else, and says so.
    func testAPasswordFailureLeavesTheRestOfTheReview() async throws {
        var output = readOutput(application: .chrome, spaces: [makeSpace(name: "Work")])
        output.passwordFailure = .unreadableDatabase
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: SequencedImportReader(results: [.success(output)]))
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        XCTAssertEqual(flow.passwordReadFailure, .unreadableDatabase)
        XCTAssertNil(flow.failure)
        XCTAssertEqual(flow.reviewSpaces.map(\.sourceSpace.settings.name), ["Work"])
    }

    /// The review shows the Spaces holding the most first, folds the empty
    /// ones away and opens on the busiest.
    func testTheReviewOrdersSpacesByContentAndFoldsEmptyOnes() async throws {
        func space(_ name: String, tabs: Int) -> SpaceState.Seed {
            SpaceState.Seed(
                name: name, symbol: "square", accent: .indigo,
                tabs: (0..<tabs).map {
                    TabState.Seed(title: "T\($0)", url: URL(string: "https://example.com/\($0)"), placement: .current)
                })
        }
        let read = readOutput(
            application: .safari, spaces: [space("Small", tabs: 1), space("Empty", tabs: 0), space("Big", tabs: 3)])
        // As a browser reads it, an empty Space holds no tabs at all.
        let output = BrowserOnboardingImportReadOutput(
            payload: read.payload,
            imported: read.imported.map { space in
                guard space.settings.name == "Empty" else { return space }
                return SpaceState(
                    id: space.id, ownProfileID: space.ownProfileID, settings: space.settings, folders: [], tabs: [],
                    splitGroups: [], archivedTabs: [], history: [], membership: space.membership,
                    importReadID: space.importReadID, profileID: space.profileID, pinOwnerID: space.pinOwnerID,
                    sidebar: space.sidebar)
            },
            passwordCandidates: [])
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: SequencedImportReader(results: [.success(output)]))
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        XCTAssertEqual(flow.reviewSpaces.map(\.sourceSpace.settings.name), ["Big", "Small"])
        XCTAssertEqual(flow.emptyReviewSpaceCount, 1)
        XCTAssertEqual(flow.review?.shownSpaceID, flow.reviewSpaces.first?.id)
        flow.showsEmptyReviewSpaces = true
        XCTAssertEqual(flow.reviewSpaces.map(\.sourceSpace.settings.name), ["Big", "Small", "Empty"])
        XCTAssertFalse(try XCTUnwrap(flow.reviewSpaces.last).isIncluded)
    }

    /// A browser that holds its password database locked, as a running one
    /// does, still has its passwords read, from a copy.
    func testPasswordsAreReadFromADatabaseTheBrowserHoldsLocked() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-login-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("Login Data").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        for statement in [
            "CREATE TABLE logins (origin_url TEXT, username_value TEXT, password_value BLOB, blacklisted_by_user INTEGER)",
            "INSERT INTO logins VALUES ('https://example.com/', 'person', x'763130aabbccdd', 0)",
            "PRAGMA locking_mode = EXCLUSIVE",
            "BEGIN EXCLUSIVE",
        ] {
            XCTAssertEqual(sqlite3_exec(database, statement, nil, nil, nil), SQLITE_OK, statement)
        }

        let candidates = try await BrowserPasswordImportReader.candidates(
            from: [ImportPasswordStore(id: "Default", profileName: "Default", path: path)], application: .chrome)

        XCTAssertEqual(candidates.map(\.origin.host), ["example.com"])
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
    }

    /// The live detached reader's typed omission and ownership reach the
    /// actual review. Closing that review releases only its own read.
    func testLiveHistoryReadFailureReachesReviewAndClosingReleasesOnlyItsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bookmarks = folder.appendingPathComponent("Bookmarks")
        try Data(
            #"{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"Kept","url":"https://kept.example/"}]}}}"#
                .utf8
        ).write(to: bookmarks)
        try Data("not a SQLite database".utf8).write(to: folder.appendingPathComponent("History"))
        let payload = BrowserDetectedImportPayload(
            application: .chrome,
            profiles: [
                ImportProfile(
                    id: "Synthetic", name: "Synthetic", bookmarksPath: bookmarks.path, sessionPath: nil,
                    profilePath: folder.path)
            ])
        let browser = BrowserStore(seed: .preview)
        let reader = LiveBrowserOnboardingImportReader(core: browser.core)
        let flow = BrowserOnboardingFlow(
            request: BrowserOnboardingRequest(entryPoint: .importBrowser), browser: browser,
            sourceDiscovery: StubSourceDiscovery(sources: [
                BrowserInstalledImportSource(
                    application: .chrome, applicationURL: folder.appendingPathComponent("Synthetic.app"),
                    detectedPayload: payload, icon: NSImage(size: NSSize(width: 64, height: 64)))
            ]),
            dataAccessProvider: StubDataAccessProvider(), importReader: reader,
            importCommitter: LiveBrowserOnboardingImportCommitter())
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let review = try XCTUnwrap(flow.review)
        XCTAssertEqual(review.leftOut.count, 1)
        guard case .historyReadFailed = try XCTUnwrap(review.leftOut.first).reason else {
            return XCTFail("The actual reader failure must reach the native review as a typed omission")
        }
        let owned = try XCTUnwrap(review.spaces.first?.source.importReadID)
        let replacement = try await reader.read(payload)
        let replacementID = try XCTUnwrap(replacement.imported.first?.importReadID)
        XCTAssertNotEqual(owned, replacementID)
        flow.cancelOperations()
        XCTAssertFalse(try browser.core.query(DiscardImportRead(readID: owned)))
        XCTAssertTrue(try browser.core.query(DiscardImportRead(readID: replacementID)))
    }

    /// Key access can complete after the window closes. Cancellation before
    /// finalization must release setup for a reread and never apply that key's
    /// late result. A no-secret retry takes the real committer path.
    func testCancellationWhileUnlockingDoesNotApplyAndCanRetryWithoutSecrets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("synthetic database".utf8).write(to: folder.appendingPathComponent("Cookies"))
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Cancelled Unlock")])
        output.profiles = [
            ImportSpaceProfile(spaceID: try XCTUnwrap(output.imported.first?.id), profilePath: folder.path)
        ]
        let secret = GatedImportSafeStorage()
        defer { secret.release() }
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: SequencedImportReader(results: [.success(output), .success(output)]),
            importCommitter: LiveBrowserOnboardingImportCommitter(
                safeStorage: secret, profileRoot: { folder }, targetKey: { throw TestFailure.read }))
        flow.start()
        flow.discoverInstalledSources()
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        flow.commitReviewedImport(afterExplaining: true)
        try await waitUntil(interval: .zero) { secret.hasStarted }
        flow.cancelOperations()
        XCTAssertFalse(flow.isCommittingImport)
        XCTAssertEqual(flow.selectedImportApplications, [.arc])
        secret.release()
        try await waitUntil(interval: .zero) { flow.importOutcomes.last?.status == .cancelled }
        XCTAssertFalse(flow.browser.spaceModels.contains { $0.settings.name == "Cancelled Unlock" })

        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        flow.importWithoutSecrets()
        try await waitUntil(interval: .zero) { flow.step == .complete }
        XCTAssertEqual(flow.importOutcomes.map(\.status), [.cancelled, .imported])
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Cancelled Unlock" })
        XCTAssertEqual(secret.readCount, 1)
    }

    /// A denied source key is a real prepare failure. Retrying uses the same
    /// reviewed choices; a corrupt synthetic cookie database is then reported
    /// as partial import, not mistaken for successful sign-in carry.
    func testDeniedArcKeyRetryKeepsConsentAndReportsActualCookieFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not a SQLite database".utf8).write(to: folder.appendingPathComponent("Cookies"))
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Arc Retry")])
        let spaceID = try XCTUnwrap(output.imported.first?.id)
        output.profiles = [ImportSpaceProfile(spaceID: spaceID, profilePath: folder.path)]
        let secret = FixtureImportSafeStorage()
        let destination = folder.appendingPathComponent("Destination", isDirectory: true)
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: SequencedImportReader(results: [.success(output)]),
            importCommitter: LiveBrowserOnboardingImportCommitter(
                safeStorage: secret, profileRoot: { destination }, targetKey: { Data(repeating: 0x22, count: 16) }))
        flow.start()
        flow.discoverInstalledSources()
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        flow.setBringsPasswords(false)
        XCTAssertTrue(flow.bringsSignIns)
        XCTAssertTrue(flow.asksForKeychainKey(try XCTUnwrap(flow.review)))
        flow.commitReviewedImport(afterExplaining: true)
        try await waitUntil(interval: .zero) { flow.keychainWasRefused }
        XCTAssertEqual(flow.importOutcomes.map(\.status), [.failed])
        XCTAssertTrue(flow.bringsSignIns)
        XCTAssertFalse(flow.bringsPasswords)
        XCTAssertFalse(flow.browser.spaceModels.contains { $0.settings.name == "Arc Retry" })

        secret.allow()
        flow.commitReviewedImport(afterExplaining: true)
        try await waitUntil(interval: .zero) { flow.step == .complete }
        XCTAssertEqual(flow.importOutcomes.map(\.status), [.failed, .imported])
        let completed = try XCTUnwrap(flow.importOutcomes.last)
        XCTAssertEqual(completed.cookieCount, 0)
        XCTAssertEqual(completed.signInSpacesSkipped, 1)
        XCTAssertFalse(completed.omissions.isEmpty)
        XCTAssertTrue(flow.browser.spaceModels.contains { $0.settings.name == "Arc Retry" })
    }

    func testLiveArcCookieOmissionsReachTheReceiptWithoutChangingTheSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cookies = folder.appendingPathComponent("Cookies")
        let key = try ChromiumPasswordCrypto.key(safeStorageSecret: "synthetic-safe-storage")
        let encrypted = try ChromiumPasswordCrypto.encrypt(
            ChromiumCookieCarryOver.sha256(".example.com") + Data("synthetic-token".utf8), key: key)
        let hex = encrypted.map { String(format: "%02x", $0) }.joined()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(cookies.path, &database), SQLITE_OK)
        let handle = try XCTUnwrap(database)
        for statement in [
            "CREATE TABLE meta (key TEXT PRIMARY KEY, value INTEGER)",
            "INSERT INTO meta VALUES ('version', 24)",
            "CREATE TABLE cookies (name TEXT, host_key TEXT, encrypted_value BLOB, has_expires INTEGER, expires_utc INTEGER)",
            "INSERT INTO cookies VALUES ('live', '.example.com', x'\(hex)', 0, 0)",
            "INSERT INTO cookies VALUES ('expired', '.example.com', x'\(hex)', 1, 1)",
            "INSERT INTO cookies VALUES ('unreadable', '.example.com', x'763130aabbccdd', 0, 0)",
        ] {
            XCTAssertEqual(sqlite3_exec(handle, statement, nil, nil, nil), SQLITE_OK)
        }
        sqlite3_close(handle)
        let sourceBytes = try Data(contentsOf: cookies)
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Arc Cookie Counts")])
        output.profiles = [
            ImportSpaceProfile(spaceID: try XCTUnwrap(output.imported.first?.id), profilePath: folder.path)
        ]
        let secret = FixtureImportSafeStorage()
        secret.allow()
        let destination = folder.appendingPathComponent("Destination", isDirectory: true)
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: SequencedImportReader(results: [.success(output)]),
            importCommitter: LiveBrowserOnboardingImportCommitter(
                safeStorage: secret, profileRoot: { destination }, targetKey: { Data(repeating: 0x22, count: 16) }))
        flow.start()
        flow.discoverInstalledSources()
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        flow.commitReviewedImport(afterExplaining: true)
        try await waitUntil(interval: .zero) { flow.step == .complete }
        let receipt = try XCTUnwrap(flow.importOutcomes.last)
        XCTAssertEqual(receipt.status, .imported)
        XCTAssertEqual(receipt.cookieCount, 1)
        XCTAssertEqual(receipt.expiredCookieCount, 1)
        XCTAssertEqual(receipt.droppedCookieCount, 1)
        XCTAssertEqual(receipt.passwordCount, 0)
        XCTAssertEqual(secret.readCount, 1)
        XCTAssertEqual(try Data(contentsOf: cookies), sourceBytes)
    }

    /// Merging retains the destination's own sign-ins and never requests a
    /// key merely because the source is Arc.
    func testArcMergeNeverUnlocksOrOverwritesDestinationCookies() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var output = readOutput(application: .arc, spaces: [makeSpace(name: "Merged Arc")])
        let sourceID = try XCTUnwrap(output.imported.first?.id)
        output.profiles = [ImportSpaceProfile(spaceID: sourceID, profilePath: folder.path)]
        let secret = FixtureImportSafeStorage()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: SequencedImportReader(results: [.success(output)]),
            importCommitter: LiveBrowserOnboardingImportCommitter(
                safeStorage: secret, profileRoot: { folder }, targetKey: { throw TestFailure.read }))
        flow.start()
        flow.discoverInstalledSources()
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let destination = try XCTUnwrap(flow.destinationSpaces.first)
        flow.setDestination(.existing(destination.id), for: sourceID)
        XCTAssertFalse(flow.asksForKeychainKey(try XCTUnwrap(flow.review)))
        flow.commitReviewedImport()
        try await waitUntil(interval: .zero) { flow.step == .complete }
        XCTAssertEqual(secret.readCount, 0)
        XCTAssertEqual(flow.importOutcomes.last?.signInSpacesSkipped, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testPasswordChoiceRestoresTheReviewedSubsetWithoutChangingSignInConsent() async throws {
        let original = readOutput(application: .chrome, spaces: [makeSpace(name: "Work"), makeSpace(name: "Home")])
        let origin = try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com"))))
        let output = BrowserOnboardingImportReadOutput(
            payload: original.payload, imported: original.imported,
            passwordCandidates: ["Work", "Home"].map {
                BrowserPasswordImportCandidate(
                    sourceApplication: .chrome, sourceProfileID: $0, sourceProfileName: $0, origin: origin)
            })
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: SequencedImportReader(results: [.success(output)]))
        flow.start()
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        try await waitUntil(interval: .zero) { flow.step == .review }
        let review = try XCTUnwrap(flow.review)
        let leftOut = try XCTUnwrap(review.spaces.first).source.id
        flow.setPasswordsIncluded(false, in: leftOut)
        let selected = Set(try XCTUnwrap(flow.review).spaces.filter(\.includesPasswords).map { $0.source.id })
        flow.setBringsPasswords(false)
        XCTAssertEqual(flow.review?.includedPasswordCount, 0)
        flow.setBringsPasswords(true)
        XCTAssertEqual(
            Set(try XCTUnwrap(flow.review).spaces.filter(\.includesPasswords).map { $0.source.id }), selected)
        XCTAssertFalse(flow.bringsSignIns, "Non-Arc browsers must not imply sign-in carry support")
    }

    private func makeFlow(
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering,
        reader: any BrowserOnboardingImportReading,
        importCommitter: any BrowserOnboardingImportCommitting = LiveBrowserOnboardingImportCommitter(),
        extensionInstaller: (any BrowserImportedExtensionInstalling)? = nil,
        entryPoint: SetupEntry = .importBrowser
    ) -> BrowserOnboardingFlow {
        BrowserOnboardingFlow(
            request: BrowserOnboardingRequest(entryPoint: entryPoint),
            browser: BrowserStore(seed: .preview),
            sourceDiscovery: sourceDiscovery,
            dataAccessProvider: StubDataAccessProvider(),
            importReader: reader,
            importCommitter: importCommitter,
            extensionInstaller: extensionInstaller
        )
    }

    private func source(
        _ application: ImportSource,
        hasDetectedData: Bool = true,
        detectedDataURL: URL? = nil
    ) -> BrowserInstalledImportSource {
        BrowserInstalledImportSource(
            application: application,
            applicationURL: URL(fileURLWithPath: "/Applications/\(application.title).app"),
            detectedPayload: BrowserDetectedImportPayload(
                application: application,
                profiles: [
                    ImportProfile(
                        id: "Default",
                        name: "Default",
                        bookmarksPath: hasDetectedData
                            ? (detectedDataURL ?? URL(fileURLWithPath: #filePath)).path
                            : nil,
                        sessionPath: nil
                    )
                ]
            ),
            icon: NSImage(size: NSSize(width: 64, height: 64))
        )
    }

    private func makeSpace(name: String) -> SpaceState.Seed {
        let tab = TabState.Seed(
            title: "Example",
            url: URL(string: "https://example.com"),
            placement: .current
        )
        return SpaceState.Seed(name: name, symbol: "square.and.arrow.down", accent: .indigo, tabs: [tab])
    }

    /// What reading `application` brings: `spaces`, as the core holds them.
    private func readOutput(
        application: ImportSource,
        spaces: [SpaceState.Seed]
    ) -> BrowserOnboardingImportReadOutput {
        BrowserOnboardingImportReadOutput(
            payload: BrowserDetectedImportPayload(application: application, profiles: []),
            imported: BrowserStore(seed: SessionState.Seed(spaces: spaces)).snapshot.spaces,
            passwordCandidates: []
        )
    }

}

/// Lists the browsers by their apps alone and records each one setup reads.
@MainActor
private struct StubSourceDiscovery: BrowserInstalledImportSourceDiscovering {
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}

/// Lists the browsers by their apps alone and records each one setup reads.
@MainActor
private final class RecordingSourceDiscovery: BrowserInstalledImportSourceDiscovering {
    private let read: [BrowserInstalledImportSource]
    private(set) var readApplications: [ImportSource] = []

    init(read: [BrowserInstalledImportSource]) {
        self.read = read
    }

    func installedSources() -> [BrowserInstalledImportSource] {
        read.map {
            BrowserInstalledImportSource(application: $0.application, applicationURL: $0.applicationURL, icon: $0.icon)
        }
    }

    func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        readApplications.append(source.application)
        return read.first { $0.id == source.id } ?? source
    }
}

private struct StubDataAccessProvider: BrowserOnboardingDataAccessProviding {
    func resolve(
        for application: ImportSource
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: ImportSource) {}

    func remember(
        _ directoryURL: URL,
        for application: ImportSource
    ) throws {}

    func chooseDataFolder(
        for application: ImportSource,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        completion(nil)
    }

    func hasSavedAccess(for application: ImportSource) -> Bool {
        false
    }
}

@MainActor
private final class PostMutationSuspendedImportCommitter:
    BrowserOnboardingImportCommitting
{
    private var finalizationContinuation: CheckedContinuation<Void, Never>?
    private var finalizationStartWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        BrowserOnboardingPreparedImport(passwords: [])
    }

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserOnboardingImportResult {
        try browser.importReviewedSpaces()
        await withCheckedContinuation { continuation in
            finalizationContinuation = continuation
            for waiter in finalizationStartWaiters {
                waiter.resume()
            }
            finalizationStartWaiters.removeAll()
        }
        return .empty
    }

    func waitUntilFinalizationStarted() async {
        guard finalizationContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            finalizationStartWaiters.append(continuation)
        }
    }

    func completeFinalization() {
        finalizationContinuation?.resume()
        finalizationContinuation = nil
    }
}

private actor SequencedImportReader: BrowserOnboardingImportReading {
    private var results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]
    private(set) var readCount = 0

    init(results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]) {
        self.results = results
    }

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        readCount += 1
        return try results.removeFirst().get()
    }
}

private actor SuspendedFlowImportReader: BrowserOnboardingImportReading {
    private var continuation:
        CheckedContinuation<
            BrowserOnboardingImportReadOutput,
            Error
        >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(_ output: BrowserOnboardingImportReadOutput) {
        continuation?.resume(returning: output)
        continuation = nil
    }
}

private enum TestFailure: LocalizedError {
    case read

    var errorDescription: String? { "The browser import could not be read." }
}

/// The OS-secret seam only: no test reads the real Keychain or a real profile.
private final class FixtureImportSafeStorage: BrowserSafeStorageSecretProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var isAllowed = false
    private var reads = 0

    var readCount: Int { lock.withLock { reads } }

    func allow() { lock.withLock { isAllowed = true } }

    func secret(for application: ImportSource) throws -> String {
        try lock.withLock {
            reads += 1
            guard isAllowed else { throw BrowserPasswordImportError.safeStorageUnavailable }
            return "synthetic-safe-storage"
        }
    }
}

/// A synchronous OS key lookup can outlive cancellation of its caller.
private final class GatedImportSafeStorage: BrowserSafeStorageSecretProviding, @unchecked Sendable {
    // MARK: - Variables

    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var reads = 0

    var readCount: Int { lock.withLock { reads } }
    var hasStarted: Bool { readCount > 0 }

    // MARK: - Actions - Key access

    func release() { gate.signal() }

    func secret(for application: ImportSource) throws -> String {
        lock.withLock { reads += 1 }
        gate.wait()
        return "synthetic-safe-storage"
    }
}
