#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import SwiftUI

    /// The harness's update commands: show going back to an earlier version
    /// with releases a feed could list, to snapshot without the network.
    extension BrowserMacHarness {
        // MARK: - Actions - Updates

        /// Presents an isolated update fixture in the sidebar, or draws its
        /// release notes without starting an updater or fetching a feed.
        func showSoftwareUpdate(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let updates = shell.application?.softwareUpdates, !updates.isEnabled else {
                throw Failure(description: "Update fixtures require an updater-disabled harness launch")
            }
            let name = arguments["stage"] as? String ?? "available"
            guard BrowserSoftwareUpdateFixture.all.contains(where: { $0.name == name }) else {
                throw Failure(description: "No update fixture is named \(name)")
            }
            updates.presentIsolatedSidebarWidgetFixture("\(name):0.8.99:899")
            if arguments["details"] as? Bool == true {
                guard let windows = shell.windows else { throw Failure(description: "The browser has no windows") }
                surfaceWindow?.close()
                windows.openSoftwareUpdateDetails()
                surfaceWindow = try window(named: BrowserMacWindowKind.updateDetails.title)
                return ["window": BrowserMacWindowKind.updateDetails.title, "scene": "software-update-details"]
            }
            return ["phase": updates.model.phase.name, "fixture": updates.model.isFixture]
        }

        /// Shows the earlier versions sheet in a window titled "Earlier
        /// versions": the list (`stage` "list") or a version ready to go back
        /// to with what it cannot keep ("ready").
        func showEarlierVersions(stage: String) -> [String: Any] {
            let releases = [("0.8.79", "202610300915", 5), ("0.8.78", "202610230910", 12)].map { version, build, days in
                BrowserSoftwareUpdateRelease(
                    version: version, build: build, publishedAt: Date(timeIntervalSinceNow: -Double(days) * 86_400),
                    archive: URL(string: "https://odebrowser.com/updates/Ode-\(version)-\(build).dmg")!,
                    length: 218_000_000, signature: "", minimumSystemVersion: "26.1", channel: nil)
            }
            let installation = BrowserSoftwareUpdateInstallation(
                bundleURL: URL(fileURLWithPath: "/Applications/Ode.app"), bundleIdentifier: "com.odebrowser.ode",
                version: "0.8.80", build: "202611021013", team: "TEAM",
                sessionVersions: [
                    BrowserSoftwareUpdateInstallation.sessionStorageVersionKey: 1,
                    BrowserSoftwareUpdateInstallation.sessionJournalVersionKey: 1,
                ],
                engineVersion: "155.0.8059.84")
            let rollback = BrowserSoftwareUpdateRollback(
                installation: installation, preferences: nil, feedURL: { nil }, allowedChannels: { [] })
            let plan =
                stage == "ready"
                ? BrowserSoftwareUpdateRollback.Plan(
                    release: releases[1],
                    stagedApp: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        .appendingPathComponent("Ode.app", isDirectory: true),
                    warnings: installation.warnings(
                        goingBackTo: ["OdeChromiumEngineVersion": "154.0.7999.12"], version: releases[1].version))
                : nil
            rollback.presentForReview(releases: releases, plan: plan)
            return show(BrowserEarlierVersionsSheet(rollback: rollback) {}, titled: "Earlier versions", width: 520)
        }
    }

#endif
