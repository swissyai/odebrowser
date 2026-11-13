import AppKit
import Foundation
import Observation
import Synchronization

/// Going back to an earlier version of Ode: the earlier releases the signed
/// feed still lists, then one of them downloaded, checked against its EdDSA
/// signature and this copy's Developer ID signature and notarization, and
/// staged beside the installed app. Going back quits Ode through its usual
/// quit and swaps the bundles once it has gone; the person's data stays
/// where it is. Sparkle never installs an older build, so this does.
@MainActor
@Observable
final class BrowserSoftwareUpdateRollback {
    // MARK: - Types

    /// An earlier version downloaded, verified and staged, waiting for the
    /// person to go back.
    struct Plan: Equatable {
        let release: BrowserSoftwareUpdateRelease
        let stagedApp: URL
        /// What the earlier version cannot keep from this one, if anything.
        let warnings: [String]
    }

    // MARK: - Static Variables

    /// Sparkle's record of a skipped update: background checks leave alone
    /// every build up to it, and a newer one is offered again.
    static let skippedBuildPreferenceKey = "SUSkippedVersion"

    // MARK: - Variables

    /// The earlier versions the feed lists that this Mac can run, newest
    /// first, once they are loaded.
    private(set) var releases: [BrowserSoftwareUpdateRelease] = []
    private(set) var isLoading = false
    /// What is under way, while a version downloads or is checked.
    private(set) var activity: String?
    private(set) var progress: Double?
    private(set) var plan: Plan?
    private(set) var failure: String?
    let installation: BrowserSoftwareUpdateInstallation

    @ObservationIgnored private let feedURL: () -> URL?
    @ObservationIgnored private let allowedChannels: () -> Set<String>
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let signingKey: BrowserSoftwareUpdateSigningKey?
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Ode was asked to quit to go back; the swap starts once the quit is
    /// allowed.
    @ObservationIgnored private var isGoingBack = false

    var unavailableReason: String? {
        signingKey == nil ? String(localized: "This copy of Ode has no update key.") : installation.unavailableReason
    }

    // MARK: - Initializers

    init(
        installation: BrowserSoftwareUpdateInstallation = BrowserSoftwareUpdateInstallation(),
        signingKey: BrowserSoftwareUpdateSigningKey? = .bundled,
        preferences: UserDefaults?,
        feedURL: @escaping () -> URL?,
        allowedChannels: @escaping () -> Set<String>
    ) {
        self.installation = installation
        self.signingKey = signingKey
        self.preferences = preferences
        self.feedURL = feedURL
        self.allowedChannels = allowedChannels
    }

    // MARK: - Actions - Choosing

    /// Reads the feed again and lists the earlier versions in it.
    func loadReleases() {
        guard unavailableReason == nil, let signingKey, let url = feedURL() else {
            failure = unavailableReason ?? String(localized: "Ode has no update feed to read.")
            return
        }
        cancel()
        isLoading = true
        failure = nil
        let build = installation.build
        let channels = allowedChannels()
        work = Task { [weak self] in
            do {
                let (feed, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                    throw BrowserSoftwareUpdateInstallation.Failure(
                        String(localized: "The update feed is unavailable."))
                }
                guard signingKey.isValidFeed(feed) else {
                    throw BrowserSoftwareUpdateInstallation.Failure(
                        String(localized: "The update feed is not signed with Ode's key."))
                }
                let system = ProcessInfo.processInfo.operatingSystemVersion
                let earlier = BrowserSoftwareUpdateRelease.releases(inFeed: feed)
                    .filter { $0.isOlder(thanBuild: build) && $0.belongs(to: channels) && $0.runs(on: system) }
                    .sorted { $0.build.compare($1.build, options: .numeric) == .orderedDescending }
                self?.finishLoading(earlier, failure: nil)
            } catch is CancellationError {
                return
            } catch {
                self?.finishLoading([], failure: error.localizedDescription)
            }
        }
    }

    /// Downloads `release`, checks it and stages it beside the installed app.
    func prepare(_ release: BrowserSoftwareUpdateRelease) {
        guard let signingKey, unavailableReason == nil else { return }
        cancel()
        failure = nil
        plan = nil
        activity = String(localized: "Downloading Ode \(release.version)…")
        progress = 0
        let installation = installation
        work = Task { [weak self] in
            // Beside the installed app's volume, so the swap is a rename.
            let folder = try? FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installation.bundleURL,
                create: true)
            do {
                guard let folder else {
                    throw BrowserSoftwareUpdateInstallation.Failure(
                        String(localized: "Ode has no room to download into."))
                }
                let image = try await Self.download(release, into: folder) { fraction in
                    Task { @MainActor in self?.progress = fraction }
                }
                try Task.checkCancellation()
                self?.activity = String(localized: "Checking Ode \(release.version)…")
                self?.progress = nil
                let plan = try await Task.detached(priority: .userInitiated) {
                    try Self.stage(release, image: image, in: folder, key: signingKey, installation: installation)
                }.value
                try Task.checkCancellation()
                self?.finishPreparing(plan, failure: nil)
            } catch {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                guard !(error is CancellationError) else { return }
                self?.finishPreparing(nil, failure: error.localizedDescription)
            }
        }
    }

    /// Stops a download or check under way, and forgets a staged version.
    func cancel() {
        work?.cancel()
        work = nil
        isLoading = false
        activity = nil
        progress = nil
        if let plan { try? FileManager.default.removeItem(at: plan.stagedApp.deletingLastPathComponent()) }
        plan = nil
    }

    // MARK: - Actions - Going back

    /// Quits Ode through its usual quit; once the quit is allowed, the staged
    /// version replaces this one and opens.
    func goBack() {
        guard plan != nil else { return }
        isGoingBack = true
        NSApp.terminate(nil)
    }

    /// The quit is allowed: Sparkle leaves the build being left alone until a
    /// newer one is out, and a process that outlives Ode swaps the bundles.
    func applicationWillQuit() {
        guard isGoingBack, let plan else { return }
        isGoingBack = false
        do {
            _ = try installation.replace(
                with: plan.stagedApp, afterExitOf: ProcessInfo.processInfo.processIdentifier)
            preferences?.set(installation.build, forKey: Self.skippedBuildPreferenceKey)
        } catch {
            DiagnosticLog.launch.notice("Ode could not go back to an earlier version: \(DiagnosticLog.describe(error))")
        }
    }

    /// The quit was declined, by a page or by the person: Ode stays as it is.
    func applicationStayedOpen() {
        guard isGoingBack else { return }
        isGoingBack = false
        failure = String(
            localized: "Ode stayed open, so it is still \(installation.version). Go back when you are ready.")
    }

    #if DEBUG || ODE_REVIEW_BUILD
        // MARK: - Actions - Review

        /// Shows `releases` and `plan` without reading the feed, for a
        /// harnessed review of the sheet.
        func presentForReview(releases: [BrowserSoftwareUpdateRelease], plan: Plan?) {
            work?.cancel()
            work = nil
            isLoading = false
            activity = nil
            progress = nil
            failure = nil
            self.releases = releases
            self.plan = plan
        }
    #endif

    // MARK: - Actions - Presentation

    private func finishLoading(_ releases: [BrowserSoftwareUpdateRelease], failure: String?) {
        isLoading = false
        work = nil
        self.releases = releases
        self.failure = failure
    }

    private func finishPreparing(_ plan: Plan?, failure: String?) {
        work = nil
        activity = nil
        progress = nil
        self.plan = plan
        self.failure = failure
    }

    // MARK: - Actions - Staging

    /// Downloads `release`'s disk image into `folder`, reporting the fraction
    /// received.
    nonisolated private static func download(
        _ release: BrowserSoftwareUpdateRelease, into folder: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let observer = BrowserSoftwareUpdateDownloadObserver(progress: progress)
        let (file, response) = try await URLSession.shared.download(from: release.archive, delegate: observer)
        let image = folder.appendingPathComponent("Ode-\(release.build).dmg")
        try FileManager.default.moveItem(at: file, to: image)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw BrowserSoftwareUpdateInstallation.Failure(
                String(localized: "Ode \(release.version) is no longer available."))
        }
        return image
    }

    /// Checks the disk image's signature before anything reads it, copies
    /// the app out of it, and checks the app against this copy of Ode.
    nonisolated private static func stage(
        _ release: BrowserSoftwareUpdateRelease, image: URL, in folder: URL, key: BrowserSoftwareUpdateSigningKey,
        installation: BrowserSoftwareUpdateInstallation
    ) throws -> Plan {
        let data = try Data(contentsOf: image, options: .alwaysMapped)
        guard Int64(data.count) == release.length, key.isValid(signature: release.signature, for: data) else {
            throw BrowserSoftwareUpdateInstallation.Failure(
                String(localized: "The download of Ode \(release.version) is not signed with Ode's key."))
        }
        // The signature proved the image; macOS need not ask about it again.
        try? (image as NSURL).setResourceValue(nil, forKey: .quarantinePropertiesKey)
        let mount = folder.appendingPathComponent("Volume", isDirectory: true)
        try run(
            "/usr/bin/hdiutil",
            ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard
            let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else {
            throw BrowserSoftwareUpdateInstallation.Failure(
                String(localized: "The download of Ode \(release.version) holds no app."))
        }
        let staged = folder.appendingPathComponent("Ode.app", isDirectory: true)
        try run("/usr/bin/ditto", [app.path, staged.path])
        try installation.verify(staged, isRelease: release)
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        try? FileManager.default.removeItem(at: image)
        let earlier = Bundle(url: staged)?.infoDictionary ?? [:]
        return Plan(
            release: release, stagedApp: staged,
            warnings: installation.warnings(goingBackTo: earlier, version: release.version))
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BrowserSoftwareUpdateInstallation.Failure(
                String(
                    localized:
                        "Ode could not prepare the earlier version (\(URL(fileURLWithPath: tool).lastPathComponent))."))
        }
    }
}

/// Reports a download's progress from the task URLSession makes for it.
private final class BrowserSoftwareUpdateDownloadObserver: NSObject, URLSessionTaskDelegate, Sendable {
    private let progress: @Sendable (Double) -> Void
    private let observation = Mutex<NSKeyValueObservation?>(nil)

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let report = progress
        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            report(progress.fractionCompleted)
        }
        self.observation.withLock { $0 = observation }
    }
}
