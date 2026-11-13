import XCTest

@testable import Ode

@MainActor
final class BrowserSetupFinishTests: XCTestCase {
    // MARK: - Actions - Finishing

    func testAnUnchangedProtectedSpaceDoesNotNeedUnlockToAddANewSpaceWithoutPractice() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        for platform in [DevicePlatform.desktop, .mobile] {
            let core = try OdeCore(
                configuration: AppConfiguration(
                    storageDirectory: nil, platform: platform, importNames: nil, restoreFrom: nil, languages: nil,
                    filterResourcesURL: nil))
            let browser = BrowserStore(seed: session, core: core)
            let protectedSettings = browser.spaceModels[0].settings
            try browser.core.send(StartSetup(workspaceID: browser.family.workspaceID, entry: .firstRun))
            try browser.core.send(ShowSetupStep(step: .manualSetup))
            let setup = BrowserManualSetupModel(core: browser.core)
            let addedID = try XCTUnwrap(setup.addSpace())
            if platform == .desktop { try browser.core.send(ShowSetupStep(step: .practice)) }
            let result = await BrowserSetupFinish.finish(
                browser: browser,
                spaceAccess: BrowserSpaceAccessController(authenticator: BrowserPreviewAuthenticator(result: false)))
            let completed = try XCTUnwrap(result as? BrowserSetupCompleted)
            XCTAssertNil(completed.guide)
            XCTAssertNotNil(browser.spaceModel(addedID))
            XCTAssertEqual(browser.spaceModel(session.spaces[0].id)?.settings.name, protectedSettings.name)
            XCTAssertEqual(browser.spaceModel(session.spaces[0].id)?.settings.accessPolicy, .deviceOwnerAuthentication)
        }
    }

    func testSkippingOptionalDesktopPracticeKeepsChosenSpacesAndRequiresUnlockBeforeApplyingThem() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: session)
        let authenticator = HeldAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        browser.attachSpaceAccess(access)
        try browser.core.send(StartSetup(workspaceID: browser.family.workspaceID, entry: .firstRun))
        try browser.core.send(ShowSetupStep(step: .manualSetup))
        let setup = BrowserManualSetupModel(core: browser.core)
        setup.nameBinding(for: session.spaces[0].id).wrappedValue = "Chosen protected Space"
        let addedID = try XCTUnwrap(setup.addSpace())
        try browser.core.send(ShowSetupStep(step: .practice))
        let before = browser.sessionSeed

        // This is the same normal finish the offer and live practice use;
        // no sample needs to have opened for the person's choices to survive.
        let refused = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        defer {
            refused.cancel()
            authenticator.resolve(false)
        }
        guard try await waitForRequest(authenticator, attempt: 1) else { return }
        authenticator.resolve(false)
        let refusal = await refused.value
        XCTAssertTrue(refusal is BrowserSetupCancelled)
        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertNotNil(setup.draft)
        XCTAssertNotEqual(browser.core.state.setupCompleted, true)

        let retry = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        defer {
            retry.cancel()
            authenticator.resolve(false)
        }
        guard try await waitForRequest(authenticator, attempt: 2) else { return }
        authenticator.resolve(true)
        let result = await retry.value
        let completed = try XCTUnwrap(result as? BrowserSetupCompleted)
        XCTAssertNil(completed.guide)
        XCTAssertEqual(browser.spaceModel(session.spaces[0].id)?.settings.name, "Chosen protected Space")
        XCTAssertEqual(browser.spaceModels.filter { $0.id == addedID }.count, 1)
        XCTAssertNil(setup.draft)
        XCTAssertEqual(browser.core.state.setupCompleted, true)
    }

    /// Changing a protected Space requires authorization. A refusal preserves
    /// the draft; retry applies it once without overwriting concurrent tab edits.
    func testARefusedUnlockLeavesSetupUnfinishedUntilARetryAppliesTheManualSetupOnce() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let core = try OdeCore(
            configuration: AppConfiguration(
                storageDirectory: nil, platform: .mobile, importNames: nil, restoreFrom: nil, languages: nil,
                filterResourcesURL: nil))
        let browser = BrowserStore(seed: session, core: core)
        let authenticator = HeldAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        browser.attachSpaceAccess(access)
        try browser.core.send(StartSetup(workspaceID: browser.family.workspaceID, entry: .firstRun))
        try browser.core.send(ShowSetupStep(step: .manualSetup))
        let setup = BrowserManualSetupModel(core: browser.core)
        let protectedID = session.spaces[0].id
        setup.nameBinding(for: protectedID).wrappedValue = "Chosen protected Space"
        let addedID = try XCTUnwrap(setup.addSpace())
        let draft = try XCTUnwrap(setup.draft)
        let before = browser.sessionSeed

        let refused = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        defer {
            refused.cancel()
            authenticator.resolve(false)
        }
        guard try await waitForRequest(authenticator, attempt: 1) else { return }
        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertEqual(setup.draft, draft)
        authenticator.resolve(false)
        let refusal = await refused.value
        XCTAssertTrue(refusal is BrowserSetupCancelled)
        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertEqual(setup.draft, draft)
        XCTAssertNotEqual(browser.core.state.setupCompleted, true)

        let retry = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        defer {
            retry.cancel()
            authenticator.resolve(false)
        }
        guard try await waitForRequest(authenticator, attempt: 2) else { return }
        let updated = browser.spaceModels[1]
        XCTAssertTrue(browser.setTabCustomTitle("Updated during setup", for: updated.tabs.models[0].id, in: updated.id))
        authenticator.resolve(true)
        guard let completed = await retry.value as? BrowserSetupCompleted else {
            return XCTFail("Setup did not complete")
        }
        XCTAssertNil(completed.guide)
        XCTAssertEqual(authenticator.attemptCount, 2)
        XCTAssertEqual(browser.spaceModel(protectedID)?.settings.name, "Chosen protected Space")
        XCTAssertEqual(browser.spaceModel(protectedID)?.settings.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(browser.spaceModels.filter { $0.id == addedID }.count, 1)
        XCTAssertEqual(browser.spaceModel(updated.id)?.tabs.models[0].customTitle, "Updated during setup")
        XCTAssertNil(setup.draft)
        XCTAssertEqual(browser.core.state.setupCompleted, true)
    }

    // MARK: - Actions - Authentication

    private func waitForRequest(_ authenticator: HeldAuthenticator, attempt: Int) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while authenticator.attemptCount < attempt, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(authenticator.attemptCount, attempt, "Setup must request authorization before applying changes")
        return authenticator.attemptCount == attempt
    }
}
