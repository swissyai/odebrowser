import XCTest

@testable import Ode

final class BrowserLaunchEnvironmentTests: XCTestCase {
    func testCloudReviewRequiresExplicitNamedIsolationAndNeverUsesTheProductionZone() throws {
        let configuration = BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.odebrowser.ode")
        let values = [
            "ODE_ISOLATED_SESSION": "1", "ODE_ISOLATED_PERSISTENCE_ID": "device-one",
            "ODE_ISOLATED_CLOUD_SYNC_ID": "shared-review",
        ]
        let review = try XCTUnwrap(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: false)))
        XCTAssertEqual(review.zoneName, "CrestReview-shared-review")
        XCTAssertNotEqual(review.zoneName, configuration.zoneName)
        for omitted in values.keys {
            var incomplete = values
            incomplete[omitted] = nil
            XCTAssertNil(
                configuration.isolated(
                    for:
                        BrowserLaunchEnvironment(values: incomplete, isXCTestRuntime: false)))
        }
        XCTAssertNil(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: true)))
        XCTAssertNil(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: false, isSwiftUIPreviewRuntime: true)))
        for invalid in ["../CrestPrivate", "Shared Review", "", String(repeating: "a", count: 49)] {
            var malformed = values
            malformed["ODE_ISOLATED_CLOUD_SYNC_ID"] = invalid
            XCTAssertNil(
                configuration.isolated(
                    for:
                        BrowserLaunchEnvironment(values: malformed, isXCTestRuntime: false)))
            XCTAssertTrue(
                BrowserLaunchEnvironment(
                    values: ["ODE_ISOLATED_CLOUD_SYNC_ID": invalid],
                    isXCTestRuntime: false
                ).requiresIsolation)
        }
    }

    func testIsolatedLaunchesNeverAdoptTheInstalledDeviceChoices() throws {
        let installedName = "BrowserLaunchEnvironmentTests.installed.\(UUID().uuidString)"
        let installed = try XCTUnwrap(UserDefaults(suiteName: installedName))
        let isolationID = "device-choices-\(UUID().uuidString.prefix(8).lowercased())"
        let isolatedName = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        let isolated = try XCTUnwrap(UserDefaults(suiteName: isolatedName))
        defer {
            installed.removePersistentDomain(forName: installedName)
            isolated.removePersistentDomain(forName: isolatedName)
        }
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.sitePermissionsKey)
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.shortcutsKey)
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.linkPreferencesKey)
        installed.set(true, forKey: BrowserLegacyDeviceDefaults.setupCompletedKey)
        isolated.set(Data("isolated".utf8), forKey: BrowserLegacyDeviceDefaults.shortcutsKey)

        let product = BrowserLegacyDeviceDefaults.read(
            for: BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false), standard: installed)
        XCTAssertEqual(product.sitePermissions, Data("installed".utf8))
        XCTAssertEqual(product.shortcuts, Data("installed".utf8))
        XCTAssertEqual(product.linkPreferences, Data("installed".utf8))
        XCTAssertTrue(product.setupCompleted)
        let namedLaunch = BrowserLaunchEnvironment(
            values: ["ODE_ISOLATED_SESSION": "1", "ODE_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
        let named = BrowserLegacyDeviceDefaults.read(for: namedLaunch, standard: installed)
        XCTAssertNil(named.sitePermissions)
        XCTAssertNil(named.linkPreferences)
        XCTAssertEqual(named.shortcuts, Data("isolated".utf8))
        XCTAssertFalse(named.setupCompleted)
        let memoryOnlyLaunch = BrowserLaunchEnvironment(
            values: ["ODE_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let memoryOnly = BrowserLegacyDeviceDefaults.read(for: memoryOnlyLaunch, standard: installed)
        XCTAssertEqual(memoryOnly, BrowserLegacyDeviceDefaults())
    }

    func testOnlyTheExactEnabledMarkerTurnsOnLaunchFlags() {
        let environment = BrowserLaunchEnvironment(
            values: [
                "ODE_ISOLATED_SESSION": "true",
                "ODE_RESET_SESSION": "true",
                "ODE_SHOWCASE_SESSION": "01",
                "ODE_USE_IN_MEMORY_CREDENTIALS": "0",
                "ODE_SHOW_ONBOARDING": "YES",
                "ODE_SHOW_SETUP": "",
                "ODE_FORCE_ONBOARDING_SETUP": "false",
            ],
            isXCTestRuntime: false
        )

        XCTAssertFalse(environment.resetsSession)
        XCTAssertFalse(environment.explicitlyRequiresIsolation)
        XCTAssertFalse(environment.presentsShowcaseSession)
        XCTAssertFalse(environment.usesInMemoryCredentialVault)
        XCTAssertFalse(environment.forcesOnboardingWelcome)
        XCTAssertFalse(environment.forcesMacOnboardingSetup)
        XCTAssertFalse(environment.forcesMobileOnboardingSetup)
        XCTAssertNil(environment.persistentIsolationID)
    }

    func testUpdateTestFeedAcceptsOnlyLoopbackHTTPURLs() {
        let rejectedValues = [
            "https://raw.githubusercontent.com/example/appcast.xml",
            "http://example.com/appcast.xml",
            "file:///tmp/appcast.xml",
        ]

        for value in rejectedValues {
            let environment = BrowserLaunchEnvironment(
                values: ["ODE_UPDATE_TEST_FEED_URL": value],
                isXCTestRuntime: false
            )
            XCTAssertNil(environment.isolatedSoftwareUpdateFeedURL)
        }
    }

    /// Each fixture input reaches the core's isolation rule through the
    /// environment's own parsing. The rule itself is the core's.
    func testEveryFixtureLaunchFlagUsesAnIsolatedDataGraph() {
        let fixtures: [[String: String]] = [
            ["ODE_ISOLATED_SESSION": "1"],
            ["ODE_RESET_SESSION": "1"],
            ["ODE_SHOWCASE_SESSION": "1"],
            ["ODE_USE_IN_MEMORY_CREDENTIALS": "1"],
            ["ODE_SHOW_ONBOARDING": "1"],
            ["ODE_SHOW_SETUP": "1"],
            ["ODE_FORCE_ONBOARDING_SETUP": "1"],
            ["ODE_ISOLATED_CLOUD_SYNC_ID": "review"],
            ["ODE_UPDATE_TEST_FEED_URL": "http://localhost:48151/appcast.xml"],
        ]

        for values in fixtures {
            XCTAssertTrue(
                BrowserLaunchEnvironment(values: values, isXCTestRuntime: false).requiresIsolation,
                "\(values) must never use the installed app's persistence graph."
            )
        }
        let tests = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
        XCTAssertTrue(tests.requiresIsolation)
        XCTAssertFalse(tests.presentsInstalledApplicationUI)
        let installed = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
        XCTAssertFalse(installed.requiresIsolation)
        XCTAssertTrue(installed.presentsInstalledApplicationUI)
    }

    /// A named isolated profile persists its WebKit storage, so it has to
    /// persist the record of what is installed as well. An anonymous isolated
    /// launch keeps forgetting both.
    func testOnlyANamedIsolatedProfileKeepsPersistentProfileStorage() {
        let named = BrowserLaunchEnvironment(
            values: [
                "ODE_ISOLATED_SESSION": "1",
                "ODE_ISOLATED_PERSISTENCE_ID": "app-252-verification",
            ],
            isXCTestRuntime: false
        )
        let anonymous = BrowserLaunchEnvironment(
            values: ["ODE_ISOLATED_SESSION": "1"],
            isXCTestRuntime: false
        )

        XCTAssertTrue(named.requiresIsolation)
        XCTAssertFalse(named.usesEphemeralProfileStorage)
        XCTAssertTrue(anonymous.usesEphemeralProfileStorage)
        XCTAssertEqual(
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            "\(ProductIdentity.serviceNamespace).isolated.app-252-verification"
        )
        XCTAssertNotEqual(
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-283-verification"
            )
        )
    }

    /// The extension pool a named isolated launch composes keeps its
    /// installations, so a validation relaunch does not begin by re-adding
    /// every extension while WebKit still holds their storage.

    /// A profile name is a directory name too, so anything that could climb
    /// out of the isolated root is refused rather than staged.

    @MainActor
    func testPersistentIsolationCanKeepItsSessionWithoutKeepingCredentials() async throws {
        let isolationID = "memory-credentials-\(UUID().uuidString.prefix(8).lowercased())"
        let namespace = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: namespace))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: namespace)
            try? FileManager.default.removeItem(at: directory)
        }
        let values = [
            "ODE_ISOLATED_SESSION": "1",
            "ODE_ISOLATED_PERSISTENCE_ID": isolationID,
            "ODE_USE_IN_MEMORY_CREDENTIALS": "1",
        ]
        let environment = BrowserLaunchEnvironment(values: values, isXCTestRuntime: false)
        let core = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let store = try BrowserStore.production(core: core, launchEnvironment: environment)
        defer { store.close() }

        // Fail before any credential operation: red must never reach the system Keychain.
        _ = try XCTUnwrap(store.credentialVault as? InMemoryCredentialVault)
        XCTAssertEqual(core.storageDirectory, directory)
        let spaceID = try XCTUnwrap(store.addSpace())
        store.updateSpaceIdentity(spaceID, name: "Persistent fixture", symbol: "globe", accent: .indigo)
        let protectionSpace = BrowserHTTPAuthenticationProtectionSpace(
            origin: try XCTUnwrap(CredentialOrigin(securityProtocol: "https", host: "fixture.ode.test", port: 443)),
            credentialScope: .httpBasic(realm: "Fixture"))
        let descriptor = try await store.saveHTTPAuthenticationCredential(
            username: "fixture-user", password: "fixture-secret", protectionSpace: protectionSpace,
            in: spaceID, now: Date(timeIntervalSince1970: 1_000))
        let saved = try await store.httpAuthenticationCredential(for: protectionSpace, in: spaceID)
        XCTAssertEqual(saved?.descriptor, descriptor)
        XCTAssertEqual(saved?.password, "fixture-secret")
        await store.flushPendingSyncPersistence()
        store.close()

        let reopenedCore = try OdeCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let reopened = try BrowserStore.production(core: reopenedCore, launchEnvironment: environment)
        defer { reopened.close() }
        _ = try XCTUnwrap(reopened.credentialVault as? InMemoryCredentialVault)
        XCTAssertEqual(reopened.spaceModel(spaceID)?.settings.name, "Persistent fixture")
        let forgotten = try await reopened.savedCredentialDescriptors(in: spaceID)
        XCTAssertTrue(forgotten.isEmpty, "Persisting a session must not persist the memory vault")

        // Deliberate named isolation still chooses its namespaced Keychain when unflagged.
        // Inspect the selection only; this branch must never perform a Keychain operation.
        var unflaggedValues = values
        unflaggedValues["ODE_USE_IN_MEMORY_CREDENTIALS"] = nil
        let unflagged = try BrowserStore.production(
            core: reopenedCore,
            launchEnvironment: BrowserLaunchEnvironment(values: unflaggedValues, isXCTestRuntime: false))
        defer { unflagged.close() }
        XCTAssertTrue(unflagged.credentialVault is KeychainCredentialVault)
    }

    @MainActor
    func testALaunchNamesOneSessionDirectoryForItsCoreAndEverythingBesideIt() throws {
        let inMemory = BrowserLaunchEnvironment(values: ["ODE_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let persistent = BrowserLaunchEnvironment(
            values: ["ODE_ISOLATED_SESSION": "1", "ODE_ISOLATED_PERSISTENCE_ID": "launch-facts"],
            isXCTestRuntime: false)

        XCTAssertNil(try BrowserStore.sessionDirectory(for: inMemory))
        XCTAssertNil(try BrowserStore.launchCore(for: inMemory).storageDirectory)
        let directory = try XCTUnwrap(BrowserStore.sessionDirectory(for: persistent))
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "Isolated")
        XCTAssertEqual(
            directory.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "ControlPlane")

        let memoryLaunch = BrowserMacLaunchContext(environment: inMemory)
        XCTAssertNil(memoryLaunch.sessionDirectory)
        XCTAssertNil(
            try BrowserStore.launchCore(sessionDirectory: memoryLaunch.sessionDirectoryResult).storageDirectory)
        XCTAssertFalse(memoryLaunch.pagesWaitAfterUncleanExit)
        XCTAssertEqual(BrowserMacLaunchContext(environment: persistent).sessionDirectory, directory)

        // A launch that could not name its directory opens recovery, naming none.
        XCTAssertThrowsError(
            try BrowserStore.launchCore(sessionDirectory: .failure(CocoaError(.fileWriteNoPermission)))
        ) { error in
            let failure = error as? BrowserSessionStartupFailure
            XCTAssertNotNil(failure)
            XCTAssertNil(failure?.storageDirectory)
        }
    }

    @MainActor
    func testProductionCompositionRedirectsFixtureInputsToInMemoryOwners() throws {
        let environments = [
            BrowserLaunchEnvironment(
                values: ["ODE_RESET_SESSION": "1"],
                isXCTestRuntime: false
            )
        ]

        for environment in environments {
            let core = try BrowserStore.launchCore(for: environment)
            XCTAssertNil(core.storageDirectory, "A fixture launch keeps its session in memory")
            let store = try BrowserStore.production(core: core, launchEnvironment: environment)

            XCTAssertTrue(store.credentialVault is InMemoryCredentialVault)
            // Only the session the core keeps in its file syncs.
            XCTAssertFalse(store.syncsSession)
        }
    }
}
