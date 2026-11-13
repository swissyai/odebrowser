import AppKit

/// Where a launch has got to, as a test harness hears it.
enum BrowserMacLaunchPhase: String, Sendable {
    /// The shell started, before any engine or the core loaded.
    case native
    /// The safe start window asks how to start.
    case safeStart
    /// The session could not open and recovery shows.
    case recovery
    /// The core opened the session and the application was built.
    case coreOpened
    /// The launch's first windows opened.
    case firstWindow
    /// The launch counts as finished in the launch record.
    case finished
}

#if DEBUG || ODE_REVIEW_BUILD

    // MARK: - Types

    /// Where a window was before `presentForCapture` moved it.
    struct BrowserMacHarnessCapturePlacement {
        let origin: NSPoint
        let level: NSWindow.Level
        let alpha: CGFloat
        let ignoresMouseEvents: Bool
    }

    /// What one page's icon lookups found: the site's `/favicon.ico` alone, as
    /// tabs that never loaded used to show, and the lookup that reads the
    /// page's head.
    struct HarnessSiteIconReport: Sendable {
        let page: String
        let defaultIconSide: Int?
        let finding: BrowserSiteIconFinding?
    }

    /// Runs a launch with nobody at the Mac, for acceptance and latency runs.
    ///
    /// `ODE_TEST_HARNESS=1` with an isolated session turns it on; it is
    /// compiled only into Debug and review builds. The app then stays out of
    /// the Dock and the menu bar, never activates, and keeps every window off
    /// the screens, still drawing. A socket beside the isolated session
    /// (`harness.sock`, mode 0600) takes newline-delimited JSON commands that
    /// act through the same paths the menus and keys do, and each launch
    /// phase is appended to `harness-phases.log` beside it, so a run can stop
    /// the app at an exact moment. First-run setup finishes as Open Ode
    /// finishes it, without reading any other browser's data.
    @MainActor
    final class BrowserMacHarness {
        // MARK: - Static Variables

        nonisolated static let environmentKey = "ODE_TEST_HARNESS"
        /// `transparent` keeps windows on screen at zero opacity instead of
        /// off the screens, for a check that needs a window on a display.
        static let windowsKey = "ODE_TEST_HARNESS_WINDOWS"
        /// `seconds[:x,y,width,height]` samples the page area from the
        /// launch's first window for that long, as `launch` beside the
        /// session; see `sampleFrames`.
        static let sampleLaunchKey = "ODE_TEST_HARNESS_SAMPLE_LAUNCH"
        /// `Key=enabled|disabled,...`: WebKit features the launch's pages
        /// start with, set once the application is built and before any page.
        static let webKitFeaturesKey = "ODE_TEST_HARNESS_WEBKIT_FEATURES"
        static let socketName = "harness.sock"
        static let phaseLogName = "harness-phases.log"

        private(set) static var shared: BrowserMacHarness?

        // MARK: - Variables

        unowned let shell: BrowserMacShell
        let directory: URL
        private var server: BrowserMacHarnessServer?
        /// The Command Bar's marks since the last time a measurement cleared them.
        var marks: [(mark: BrowserCommandBarTiming.Mark, at: UInt64)] = []
        /// Finishes first-run setup the way Open Ode does.
        private var completeSetup: (@MainActor () -> Void)?
        private(set) var phases: [BrowserMacLaunchPhase] = []
        /// A surface shown again in a window of its own, for a snapshot.
        var surfaceWindow: NSWindow?
        /// Where each window `presentForCapture` moved was, to put it back.
        var capturePlacements: [Int: BrowserMacHarnessCapturePlacement] = [:]
        /// The last staged player report's sequence.
        var mediaSequence: UInt64 = 0
        /// Takes the staged players' controls.
        let mediaEndpoint = BrowserMacHarnessMediaEndpoint()

        /// Whether this launch runs under the harness, which keeps it out of
        /// the system's shared surfaces such as Now Playing.
        static var isRunning: Bool { shared != nil }

        // MARK: - Initializers

        private init(shell: BrowserMacShell, directory: URL) {
            self.shell = shell
            self.directory = directory
        }

        // MARK: - Actions - Launch

        /// Whether `values` turn the harness on: its variable, with an
        /// isolated session, so it can never run over the person's own.
        nonisolated static func isRequested(_ environment: BrowserLaunchEnvironment, values: [String: String]) -> Bool {
            values[environmentKey] == "1" && environment.requiresIsolation
        }

        /// Turns the harness on for this launch when its variable asks, before
        /// the shell opens a window. Its socket and phase log sit beside the
        /// session `launch` names.
        static func attach(to shell: BrowserMacShell, launch: BrowserMacLaunchContext) {
            let values = ProcessInfo.processInfo.environment
            guard shared == nil, isRequested(launch.environment, values: values),
                let directory = launch.sessionDirectory
            else { return }
            let harness = BrowserMacHarness(shell: shell, directory: directory)
            shared = harness
            NSApp.setActivationPolicy(.accessory)
            BrowserMacHarnessWindows.install(transparent: values[windowsKey] == "transparent")
            BrowserCommandBarTiming.observer = { [weak harness] mark, at in harness?.marks.append((mark, at)) }
            harness.server = BrowserMacHarnessServer(directory: directory, name: socketName) { request in
                await harness.reply(to: request)
            }
            harness.record(.native)
        }

        static func phase(_ phase: BrowserMacLaunchPhase) {
            shared?.record(phase)
        }

        /// First-run setup showed; the harness finishes it once the setup
        /// flow has started, as Open Ode does after Set Up by Hand.
        static func onboardingShown(complete: @escaping @MainActor () -> Void) {
            guard let shared else { return }
            shared.completeSetup = complete
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                shared.completeSetup?()
                shared.completeSetup = nil
            }
        }

        private func record(_ phase: BrowserMacLaunchPhase) {
            phases.append(phase)
            if phase == .coreOpened, let request = ProcessInfo.processInfo.environment[Self.webKitFeaturesKey] {
                setWebKitFeatures(request)
            }
            if phase == .firstWindow, let request = ProcessInfo.processInfo.environment[Self.sampleLaunchKey] {
                sampleLaunch(request)
            }
            let line = "\(phase.rawValue) \(DispatchTime.now().uptimeNanoseconds) \(Date().timeIntervalSince1970)\n"
            let url = directory.appendingPathComponent(Self.phaseLogName)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }

        private func setWebKitFeatures(_ request: String) {
            let store = BrowserWebKitFeatureFlagStore.active
            for pair in request.split(separator: ",") {
                let parts = pair.split(separator: "=").map(String.init)
                guard parts.count == 2, let flag = store.features.first(where: { $0.key == parts[0] }),
                    let value = BrowserWebKitFeatureFlagOverride(rawValue: parts[1])
                else { continue }
                store.setOverride(value, for: flag)
            }
        }

        private func sampleLaunch(_ request: String) {
            let parts = request.split(separator: ":")
            var arguments: [String: Any] = [
                "name": "launch", "lead": 0.0, "duration": parts.first.flatMap { Double($0) } ?? 3,
            ]
            if parts.count > 1 { arguments["area"] = parts[1].split(separator: ",").compactMap { Double($0) } }
            Task { @MainActor in _ = try? await sampleFrames(arguments) }
        }
    }

#else

    /// The harness is compiled only into Debug and review builds; a release
    /// build answers every hook with nothing.
    @MainActor
    enum BrowserMacHarness {
        static var isRunning: Bool { false }
        static func attach(to shell: BrowserMacShell, launch: BrowserMacLaunchContext) {}
        static func phase(_ phase: BrowserMacLaunchPhase) {}
        static func onboardingShown(complete: @escaping @MainActor () -> Void) {}
    }

#endif
