import AppKit

/// Ode's Mac application shell, which either engine's product runs: the
/// launch, or recovery when the session cannot open; the windows the core
/// restores; the menu bar; reopen and the Dock menu; links and documents from
/// other apps and system sign-in; the engine's own windows; and quit. The
/// engine that owns the process asks it through its entry points and answers
/// the little only it can through its `BrowserMacEngineHost`.
@MainActor
final class BrowserMacShell {
    // MARK: - Types

    /// What runs once the launch built the application.
    private struct Running {
        let application: BrowserMacApplication
        let windows: BrowserMacWindows
        let quit: BrowserMacQuit
        let menuBar: BrowserMacMenuBar
        let dockMenu: BrowserMacDockMenu
        let externalOpening: BrowserMacExternalOpening
        let agents: BrowserMacAgents
    }

    /// A system sign-in that arrived before the launch finished.
    private struct PendingSignIn {
        let url: URL
        let windowID: UUID
        let declined: @MainActor () -> Void
    }

    // MARK: - Variables

    let engineHost: any BrowserMacEngineHost
    private var launch: BrowserApplicationLaunch<BrowserMacApplication>?
    private var recovery: BrowserMacLaunchRecovery?
    /// The safe start window, while the launch waits for the person's choice.
    private var safeStart: BrowserMacSafeStart?
    private var running: Running?
    /// Links and documents other apps handed over before the launch finished,
    /// which can be while recovery is on screen; they open once it has.
    private var pendingOpens: [URL] = []
    private var pendingSignIns: [PendingSignIn] = []
    /// Offers every key down to `handleShortcut` before any view sees it.
    /// Both engines' page views take key equivalents before the menu bar
    /// does, so this is where Ode's shortcuts go ahead of a page when their
    /// preference says so, and ahead of Ode's own views always.
    private var keyMonitor: Any?
    /// The New Quick Window keys, which reach Ode from other apps.
    private var quickWindowShortcut: BrowserMacGlobalShortcut?
    /// Takes a mouse's Back and Forward clicks whole in every window, ahead of
    /// any view.
    private let mouseButtons = BrowserMacMouseButtons()
    /// The recent tabs a held Most Recent Tab shortcut shows.
    let recentTabSwitcher = BrowserMacRecentTabSwitcher()
    /// The last press of a Use Both shortcut a focused page saw first.
    let pageKeptShortcut = BrowserMacPageKeptShortcut()
    /// This launch's facts, resolved once as it starts and handed to all it
    /// builds.
    private var context: BrowserMacLaunchContext?
    /// Marks a quit before the application ran, from recovery, as clean.
    private var terminationObserver: (any NSObjectProtocol)?
    /// The updater, started before the application so recovery can install a
    /// fixed version.
    private(set) var softwareUpdates: BrowserSoftwareUpdateService?
    /// Why the copy the last launch asked this one to restore was not put in
    /// place; the restore window says so once the browser runs.
    private var requestedRestoreFailure: String?
    /// Times the main thread while the browser runs, into the hang log beside
    /// the session.
    private var watchdog: BrowserMainThreadWatchdog?

    /// This launch's entry beside the session, opened before any engine
    /// loads; nil when the launch keeps its session in memory.
    var launchRecord: BrowserLaunchRecord? { context?.launchRecord }

    /// The directory the session is kept in, beside the launch record; nil
    /// when the launch keeps its session in memory.
    var sessionDirectory: URL? { context?.sessionDirectory }

    /// The application, once the launch built it.
    var application: BrowserMacApplication? { running?.application }
    /// The windows, once the launch built the application.
    var windows: BrowserMacWindows? { running?.windows }
    /// Whether a quit is being prepared or finished, so nothing new opens.
    var isQuitting: Bool { running?.quit.isQuitting ?? false }

    // MARK: - Initializers

    init(engineHost: any BrowserMacEngineHost) {
        self.engineHost = engineHost
    }

    // MARK: - Actions - Launch

    /// Builds the application with `factory` and opens what the core says the
    /// launch opens, or shows recovery when the session cannot open and
    /// continues from there once it can. A retry runs `factory` again. Before
    /// either, the launch is recorded and the updater starts. When the last
    /// launch did not finish starting, it looks for a fixed version at once;
    /// after two such launches in a row, or with Shift held, the safe start
    /// window asks how to start before any engine loads. The session
    /// directory and the launch environment are resolved once, here, into
    /// the context everything the launch builds reads. A composition
    /// prepares the launch environment first; see
    /// `BrowserMacApplication.prepareLaunchEnvironment(reviewPersistenceID:)`.
    func start(launching factory: @escaping @MainActor (BrowserMacLaunchContext) throws -> BrowserMacApplication) {
        guard launch == nil, safeStart == nil else { return }
        var context = BrowserMacLaunchContext()
        BrowserSiteBackgrounds.openShared(in: context.sessionDirectory)
        context.launchRecord = openLaunchRecord(in: context.sessionDirectory)
        BrowserMacHarness.attach(to: self, launch: context)
        restoreRequestedCopy(in: context.sessionDirectory)
        let environment = context.environment
        let softwareUpdates = BrowserSoftwareUpdateService.forLaunch(environment)
        self.softwareUpdates = softwareUpdates
        context.softwareUpdates = softwareUpdates
        self.context = context
        let failedStarts = launchRecord?.startupStreak ?? 0
        let decision = BrowserLaunchSafety.decide(
            failedStarts: failedStarts, safeModeFailed: launchRecord?.safeModeFailed ?? false,
            shiftHeld: NSEvent.modifierFlags.contains(.shift),
            promptsAllowed: BrowserLaunchSafety.promptsAllowed(environment, values: ProcessInfo.processInfo.environment)
        )
        if failedStarts > 0 { softwareUpdates.checkAfterFailedStart() }
        guard case .start = decision else {
            DiagnosticLog.launch.notice("Asking how to start after \(failedStarts) failed starts")
            BrowserMacHarness.phase(.safeStart)
            let safeMode = BrowserSafeMode()
            safeStart = BrowserMacSafeStart(
                decision: decision, safeMode: safeMode, softwareUpdates: softwareUpdates,
                storageDirectory: sessionDirectory, restoreEarlierCopy: restoreBeforeOpening()
            ) { [weak self, context] choice in
                guard let self else { return }
                safeStart = nil
                var chosen = context
                if choice == .safeMode {
                    launchRecord?.enterSafeMode()
                    chosen.safeMode = safeMode
                }
                proceed(factory, context: chosen)
            }
            return
        }
        proceed(factory, context: context)
    }

    // MARK: - Actions - Hangs

    /// Starts timing the main thread, keeping each hang in the log beside the
    /// session and in the moments, tagged with the moment in flight. Only the
    /// watchdog's thread writes the log.
    private func startWatchdog() {
        guard watchdog == nil, let directory = sessionDirectory else { return }
        let watchdog = BrowserMainThreadWatchdog { start, seconds in
            // The main thread answered just now, so the hang ends now, on
            // the moments' clock of system uptime.
            let end = DispatchTime.now().uptimeNanoseconds
            var log = BrowserHangLog.read(in: directory)
            log.record(start: start, seconds: seconds)
            log.write(in: directory)
            let began = end - min(end, UInt64(seconds * 1_000_000_000))
            Task { @MainActor in BrowserMoments.shared.recordHang(at: start, from: began, to: end) }
        }
        watchdog.start()
        self.watchdog = watchdog
    }

    /// Collects the reports the launch record, macOS's crash reports and the
    /// hang log hold that the store has not seen, off the main thread where it
    /// reads files, and sends them when the person chose to always send.
    private func collectReports(for application: BrowserMacApplication) {
        guard let reports = application.crashReports, let record = launchRecord else { return }
        let history = record.history
        let current = record.currentID
        let directory = sessionDirectory
        let build = Self.build
        let isolated = context?.environment.requiresIsolation ?? true
        Task { @MainActor in
            let now = Date()
            let crashes = await Task.detached(priority: .utility) {
                BrowserCrashReportReaders.crashes(now: now, launches: history.launches, isolated: isolated)
            }.value
            reports.confirmCrashOwnership(Set(crashes.map(\.id)))
            let hangs = directory.map {
                BrowserCrashReportReaders.hangs(in: BrowserHangLog.read(in: $0), build: build, now: now)
            }
            let new = reports.collect(
                BrowserCrashReportReaders.launches(in: history, current: current, now: now) + (hangs ?? []) + crashes)
            await reports.sendNewIfChosen(new)
        }
    }

    // MARK: - Actions - Moments

    /// Records how long the launch took: from the process starting to the
    /// restored session's windows opening, with the tabs that did not come
    /// back where the last clean quit left them, and to the first window's
    /// first frame, warm when Ode ran before since the Mac started.
    private func recordLaunch(of application: BrowserMacApplication) {
        guard let start = BrowserMoments.processStart() else { return }
        let moments = BrowserMoments.shared
        moments.record(.sessionRestore, from: start)
        if let directory = sessionDirectory, launchRecord?.previousLaunchEndedUncleanly == false,
            let saved = BrowserSessionShape.read(in: directory)
        {
            let found = Self.sessionShape(of: application).compared(with: saved)
            moments.count(.restoreDifferences, by: found.total)
            if found.total > 0 {
                DiagnosticLog.launch.notice(found.line { Self.tabKind($0, in: application) })
            }
        }
        let warm = BrowserMoments.bootDate.map { launchRecord?.launchedEarlier(since: $0) == true } ?? false
        moments.afterNextCommit { moments.record(warm ? .launchWarm : .launchCold, from: start) }
    }

    /// What kind of tab `id` is, as the restore line names an added one: its
    /// section, and whether it is a Start Page.
    private static func tabKind(_ id: UUID, in application: BrowserMacApplication) -> String? {
        let tab = application.browser.spaceModels.lazy.compactMap { $0.tabs.model(id) }.first
        return tab.map { $0.placement.name + ($0.isStartPage ? " Start Page" : "") }
    }

    /// Which tabs each Space of the application holds, in order.
    private static func sessionShape(of application: BrowserMacApplication) -> BrowserSessionShape {
        BrowserSessionShape(
            spaces: application.browser.spaceModels.map { .init(id: $0.id, tabs: $0.tabs.models.map(\.id)) })
    }

    // MARK: - Actions - Earlier copies

    /// Puts in place the copy of the session the last launch asked for, before
    /// anything opens the session. A copy that cannot be restored leaves the
    /// session as it was, and the restore window says so once the browser runs.
    private func restoreRequestedCopy(in directory: URL?) {
        guard let directory, let name = BrowserRecoveryCopies.takeRequest(in: directory) else { return }
        guard let copy = BrowserRecoveryCopies.list(in: directory).first(where: { $0.name == name }) else {
            requestedRestoreFailure = String(localized: "The copy you chose is no longer kept. Nothing was changed.")
            return
        }
        do {
            try BrowserRecoveryCopies.restore(copy, in: directory)
            DiagnosticLog.launch.notice("Restored the session copy taken \(copy.takenAt)")
        } catch {
            DiagnosticLog.launch.notice(
                "The requested session copy could not be restored: \(DiagnosticLog.describe(error))")
            requestedRestoreFailure = String(localized: "That copy couldn't be restored. Nothing was changed.")
        }
    }

    /// Offers the dated copies before the session opens, from the safe start
    /// window: a copy chosen there is put in place at once. Nil when there is
    /// no copy to offer.
    private func restoreBeforeOpening(restored: (@MainActor () -> Void)? = nil) -> (@MainActor () -> Void)? {
        guard let directory = sessionDirectory, !BrowserRecoveryCopies.list(in: directory).isEmpty else { return nil }
        return { BrowserMacRestoreWindow.show(directory: directory, timing: .now) { _ in restored?() } }
    }

    /// The File menu's restore: the dated copies, one of which Ode restores
    /// as it quits and opens again.
    func restoreEarlierCopy() {
        guard let directory = sessionDirectory else { return }
        BrowserMacRestoreWindow.show(directory: directory, timing: .relaunch)
    }

    /// Whether the session is kept on disk, so earlier copies can exist.
    var canRestoreEarlierCopy: Bool { sessionDirectory != nil && running != nil }

    /// Whether the safe start window is asking how to start.
    var isAskingHowToStart: Bool { safeStart != nil }

    /// Whether recovery shows because the session could not open.
    var isShowingRecovery: Bool { recovery != nil }

    private func proceed(
        _ factory: @escaping @MainActor (BrowserMacLaunchContext) throws -> BrowserMacApplication,
        context: BrowserMacLaunchContext
    ) {
        let softwareUpdates = context.softwareUpdates
        let launch = BrowserApplicationLaunch { try factory(context) }
        self.launch = launch
        if let application = launch.value {
            BrowserMacHarness.phase(.coreOpened)
            run(application)
        } else {
            BrowserMacHarness.phase(.recovery)
            recovery = BrowserMacLaunchRecovery(
                launch: launch, softwareUpdates: softwareUpdates,
                restoreEarlierCopy: restoreBeforeOpening { [weak launch] in launch?.retry() }
            ) { [weak self] in
                self?.run($0)
            }
        }
    }

    /// Runs the application the launch built. A test host builds it and
    /// shows nothing: no window, menu, Dock tile or sync of its own.
    private func run(_ application: BrowserMacApplication) {
        guard running == nil else { return }
        let windows = BrowserMacWindows(application: application, engineHost: engineHost)
        let menuBar = BrowserMacMenuBar(
            shell: self, shortcuts: application.shortcuts, state: application.browser.core.state)
        running = Running(
            application: application, windows: windows,
            quit: BrowserMacQuit(application: application, windows: windows), menuBar: menuBar,
            dockMenu: BrowserMacDockMenu(application: application, windows: windows),
            externalOpening: BrowserMacExternalOpening(application: application, windows: windows),
            agents: BrowserMacAgents(application: application, windows: windows))
        recovery?.close()
        recovery = nil
        guard application.presentsInstalledApplicationUI else { return }
        BrowserMacAppearance.shared.start()
        BrowserMacDockTile.shared.start(following: application.browser.core)
        let background = application.launchesInBackground
        windows.openLaunchWindows(activation: background ? .background : .key)
        BrowserMacHarness.phase(.firstWindow)
        recordLaunch(of: application)
        menuBar.install()
        finishLaunchRecordOnceSettled()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let pageSeesFirst = BrowserWebHostView.isPageContent(NSApp.keyWindow?.firstResponder)
            // Typing into a page asks whether it still answers.
            if pageSeesFirst { self?.windows?.activeContext?.pages.activePage?.responsiveness.interacted() }
            let stage: BrowserMacKeyStage = pageSeesFirst ? .beforePage : .beforeOdeView
            return self?.handleShortcut(event, at: stage) == true ? nil : event
        }
        quickWindowShortcut = BrowserMacGlobalShortcut(
            binding: { application.shortcuts.shortcut(for: .newQuickWindow) },
            pressed: { [weak self] in self?.quickWindowShortcutPressed() })
        quickWindowShortcut?.start()
        mouseButtons.start()
        startWatchdog()
        collectReports(for: application)
        recentTabSwitcher.start(in: self)
        running?.agents.start()
        // Safe mode leaves sync and filter list updates paused for this
        // launch; nothing it keeps changes.
        if application.safeMode == nil {
            application.filterLists.start()
            Task { await application.cloudSync.start() }
        }
        if !background { NSApp.activate(ignoringOtherApps: true) }
        openPending()
        if let failure = requestedRestoreFailure, let directory = sessionDirectory {
            requestedRestoreFailure = nil
            BrowserMacRestoreWindow.show(directory: directory, timing: .relaunch, failure: failure)
        }
    }

    private func openPending() {
        let opens = pendingOpens
        let signIns = pendingSignIns
        pendingOpens = []
        pendingSignIns = []
        if !opens.isEmpty { _ = openExternal(opens) }
        for signIn in signIns {
            _ = openAuthenticationSession(signIn.url, window: signIn.windowID, declined: signIn.declined)
        }
    }

    // MARK: - Actions - Launch record

    /// Opens this launch's entry in the record beside the session in
    /// `directory`, before any engine loads, so a launch that never finishes
    /// starting is counted. Nil when the launch keeps its session in memory.
    private func openLaunchRecord(in directory: URL?) -> BrowserLaunchRecord? {
        guard let directory else { return nil }
        let record = BrowserLaunchRecord(directory: directory)
        record.begin(
            build: Self.build, processID: Int(getpid()),
            processStartedAt: BrowserMoments.processStartDate()?.timeIntervalSince1970)
        BrowserMoments.shared.open(in: directory)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                BrowserSiteBackgrounds.shared.saveNow()
                // A quit from recovery is the person's own; once the
                // application runs, its quit marks the launch.
                guard let self, self.running == nil else { return }
                self.launchRecord?.endCleanly()
            }
        }
        return record
    }

    /// Marks the launch finished once its first windows have stayed up.
    private func finishLaunchRecordOnceSettled() {
        guard let launchRecord else { return }
        Task { @MainActor [weak launchRecord] in
            try? await Task.sleep(for: BrowserLaunchRecord.finishingDelay)
            launchRecord?.finish()
            BrowserMacHarness.phase(.finished)
        }
    }

    /// The version and build this launch runs, as the record names it.
    static var build: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: - Actions - Application

    /// A quit the application was asked for, which `finish` completes once the
    /// core allowed it and every edit is saved, or with false when it did not.
    /// Answers false when there is nothing to hold, before the launch finished
    /// or once the quit was finished, so the entry point quits at once.
    func requestQuit(finish: @escaping @MainActor (_ allowed: Bool) -> Void) -> Bool {
        guard let running else { return false }
        return running.quit.request { [weak self] allowed in
            // No agent reaches an Ode that is going.
            if allowed {
                running.agents.stop()
                self?.launchRecord?.endCleanly()
                if let directory = self?.sessionDirectory {
                    Self.sessionShape(of: running.application).write(in: directory)
                }
                BrowserMoments.shared.saveNow()
            }
            finish(allowed)
        }
    }

    /// A Dock click or `Open` with no Ode window. An open window comes
    /// forward; with none, setup does while it holds the launch back, and
    /// otherwise the window the core names opens. Answers false when the shell
    /// is not running or is quitting.
    func reopen() -> Bool {
        guard let running, !running.quit.isQuitting else { return false }
        let application = running.application
        if let window = running.windows.windowToBringForward {
            window.bringForward()
        } else if let setup = try? application.browser.core.query(
            LaunchSetup(environment: application.launchEnvironment)
        ).setup {
            running.windows.openOnboardingWindow(BrowserOnboardingRequest(entryPoint: setup))
        } else if let reopened = try? application.browser.core.query(
            WindowToReopen(windowIDs: application.stackedWindowIDs))
        {
            running.windows.open(.reopening(reopened.windowID), activation: .key)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The Dock icon's menu: Ode's window commands and Spaces, ahead of the
    /// window list and the items macOS adds itself.
    func dockMenu() -> NSMenu? {
        guard let running, !running.quit.isQuitting else { return nil }
        return running.dockMenu.menu()
    }

    /// The New Quick Window keys, pressed in another app. No Ode window is
    /// key there, so they run as the Dock menu does, over the window the
    /// person is in.
    private func quickWindowShortcutPressed() {
        guard let running, !running.quit.isQuitting else { return }
        running.dockMenu.openQuickWindowWherePersonIs()
    }

    // MARK: - Actions - External opens

    /// Links and documents from other apps, opened where the core places them
    /// once the launch finished. Answers whether Ode takes them, which it
    /// does for every one it accepts.
    func openExternal(_ urls: [URL]) -> Bool {
        let accepted = urls.filter {
            $0.isFileURL ? ExternalLocalDocument.accepts($0) : ExternalWebLink.accepts($0)
        }
        guard !accepted.isEmpty else { return true }
        guard let running else {
            pendingOpens.append(contentsOf: accepted)
            return true
        }
        Task { @MainActor in await running.externalOpening.open(accepted) }
        return true
    }

    // MARK: - Actions - System sign-in

    /// An app's `ASWebAuthenticationSession` sign-in. It lands in the Space a
    /// link from that app routes to, always as a Quick Window named
    /// `windowID`: the session is transient and the engine closes the window
    /// when the page reaches the app's callback. `declined` runs when the core
    /// places it nowhere, so the app learns at once. Answers whether Ode
    /// takes it.
    func openAuthenticationSession(
        _ url: URL, window windowID: UUID, declined: @escaping @MainActor () -> Void
    ) -> Bool {
        guard ExternalWebLink.accepts(url) else { return false }
        guard let running else {
            pendingSignIns.append(PendingSignIn(url: url, windowID: windowID, declined: declined))
            return true
        }
        Task { @MainActor in
            guard let destination = await running.externalOpening.destination(for: url) else {
                declined()
                return
            }
            running.windows.openQuickWindow(
                BrowserQuickWindowRequest(
                    id: windowID, url: url, spaceAssignment: destination.assignment,
                    targetWindowID: destination.quickWindowTarget, opensWherePersonIs: true))
            guard let window = running.windows.quickWindow(windowID) else {
                declined()
                return
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// The sign-in in the Quick Window `windowID` is over; a before-unload
    /// prompt would only get in the way.
    func closeAuthenticationSession(_ windowID: UUID) {
        running?.windows.closeQuickWindowWithoutAsking(windowID)
    }

    // MARK: - Actions - Engine windows

    /// The window open under the core's identity `id`, or with none, the
    /// window an engine surface with no window of its own is shown in.
    func window(for id: UUID?) -> NSWindow? {
        running?.windows.window(for: id)
    }

    /// Reserves the Ode window that will host a browser the engine created
    /// for itself and names the Space its tabs belong to, as the core places
    /// them over the windows as AppKit stacks them.
    ///
    /// Ode is one window. The browser's tabs join the window the person is
    /// using, and only one an extension asked for by name (`ownWindow`) opens
    /// another. Nothing is presented here: the engine creates the browser
    /// first and offers its tabs afterwards. The core declines a profile with
    /// no Space to host it, so the engine drops those tabs rather than routing
    /// them into an unrelated Space, an off-the-record profile once the
    /// private window is closed, and a Space that is locked or being deleted.
    func reserveEngineWindow(forProfile profileID: UUID, ownWindow: Bool) -> (window: UUID, space: UUID)? {
        guard let running, !running.quit.isQuitting else { return nil }
        let application = running.application
        guard
            let place = try? application.browser.core.query(
                EngineWindowPlacement(
                    profileID: profileID, ownWindow: ownWindow, windowIDs: application.stackedWindowIDs)),
            let window = place.windowID, let space = place.spaceID
        else { return nil }
        return (window, space)
    }

    /// Opens the window reserved for an engine-created browser, just before
    /// its first tab is offered for adoption, coming forward as `focused`
    /// says.
    func presentEngineWindow(_ windowID: UUID, space spaceID: UUID, focused: Bool) {
        guard let running, !running.quit.isQuitting else { return }
        let windows = running.windows
        if windows.isPrivateWindow(windowID) {
            if focused { windows.window(for: windowID)?.makeKeyAndOrderFront(nil) }
            return
        }
        windows.open(BrowserMacWindowRequest(id: windowID, kind: .normal), activation: focused ? .key : .background)
        guard windows.isBrowserWindowOpen(windowID) else { return }
        running.application.selectSpace(spaceID, in: windowID)
        if focused { NSApp.activate(ignoringOtherApps: true) }
    }
}
