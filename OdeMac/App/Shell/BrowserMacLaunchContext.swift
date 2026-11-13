import Foundation

/// The facts of this launch, which the shell resolves once before any engine
/// loads and everything it builds reads instead of resolving its own: how the
/// process was launched; the directory the session is kept in, or why the
/// launch could not name one; this launch's entry in the record beside the
/// session; the updater, started before the session opens, so a fixed version
/// can still arrive when the session or the engine cannot start; and safe
/// mode when the person chose it for this launch.
@MainActor
struct BrowserMacLaunchContext {
    // MARK: - Variables

    let environment: BrowserLaunchEnvironment
    /// The directory the session is kept in, nil when the launch keeps it in
    /// memory, or the failure that left the launch without one. A launch that
    /// cannot name its directory opens recovery, and a retry within the same
    /// launch meets the same failure, so the core, the launch record and the
    /// files beside the session never disagree about where it is.
    let sessionDirectoryResult: Result<URL?, any Error>
    /// This launch's entry in the record beside the session; nil when the
    /// launch keeps its session in memory.
    var launchRecord: BrowserLaunchRecord?
    var softwareUpdates: BrowserSoftwareUpdateService?
    var safeMode: BrowserSafeMode?

    /// The directory the session is kept in; nil when the launch keeps it in
    /// memory or could not name one.
    var sessionDirectory: URL? { try? sessionDirectoryResult.get() }

    /// Whether the launch before ended without a quit the person asked for,
    /// which leaves every page to load when it is opened.
    var pagesWaitAfterUncleanExit: Bool { launchRecord?.previousLaunchEndedUncleanly ?? false }

    // MARK: - Initializers

    /// The facts of a launch in `environment`, naming its session directory
    /// once; a failure to name one is logged here.
    init(environment: BrowserLaunchEnvironment = .current) {
        self.environment = environment
        sessionDirectoryResult = Result { try BrowserStore.sessionDirectory(for: environment) }
        if case .failure(let error) = sessionDirectoryResult {
            DiagnosticLog.launch.error(
                "The session directory could not be named; nothing is kept beside the session: "
                    + "\(DiagnosticLog.describe(error))")
        }
    }
}
