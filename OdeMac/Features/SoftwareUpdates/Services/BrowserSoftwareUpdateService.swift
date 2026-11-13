import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class BrowserSoftwareUpdateService {
    // MARK: - Static Variables

    static let channelPreferenceKey = "crest.software-update.channel"
    static let bundledChannelPreferenceKey =
        "crest.software-update.bundled-channel"
    static let defaultChannelInfoKey = "OdeDefaultUpdateChannel"
    static let reminderPreferenceKey = "ode.software-update.remind-after"
    /// The hidden preference that points Ode at a feed served on this Mac, to
    /// try an update before it is published. Only an `http` address on this
    /// Mac counts, on every channel; Sparkle's own reading of the same key is
    /// never reached, because the feed is always named here.
    static let localFeedPreferenceKey = "SUFeedURL"

    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel
    let widgetSource: BrowserSoftwareUpdateWidgetSource
    /// Restarts to finish an update while the Mac is idle, when turned on.
    @ObservationIgnored let idleRestart: BrowserIdleRestart
    var restartsWhenIdle: Bool {
        didSet { idleRestart.isEnabled = restartsWhenIdle }
    }
    private(set) var isEnabled: Bool
    private(set) var startErrorDescription: String?
    /// The feed on this Mac that the hidden preference names, as last read.
    private(set) var localFeedURL: URL?
    /// Going back to an earlier version.
    let rollback: BrowserSoftwareUpdateRollback
    var channel: BrowserSoftwareUpdateChannel {
        didSet {
            userDriver.channel = channel
            preferences?.set(channel.name, forKey: Self.channelPreferenceKey)
            guard isEnabled else { return }
            refreshCoordinator.channelDidChange()
        }
    }

    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let userDriver: BrowserSoftwareUpdateUserDriver
    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let refreshCoordinator: BrowserSoftwareUpdateRefreshCoordinator
    @ObservationIgnored private var reminder: Task<Void, Never>?
    @ObservationIgnored private var automaticPreferenceObservations: [NSKeyValueObservation] = []
    private var automaticPreferenceRevision = 0
    private var fixtureAutomaticallyChecks = true
    private var fixtureAutomaticallyDownloads = true

    var automaticallyChecksForUpdates: Bool {
        if model.isFixture { return fixtureAutomaticallyChecks }
        _ = automaticPreferenceRevision
        return updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        if model.isFixture { return fixtureAutomaticallyDownloads }
        _ = automaticPreferenceRevision
        return updater.automaticallyDownloadsUpdates
    }

    var automaticUpdatesEnabled: Bool {
        automaticallyChecksForUpdates && automaticallyDownloadsUpdates
    }

    // MARK: - Initializers

    init(
        isEnabled: Bool,
        preferences: UserDefaults? = .standard,
        defaultChannel: BrowserSoftwareUpdateChannel? = nil,
        feedURLOverride: URL? = nil
    ) {
        let bundledDefaultChannel =
            defaultChannel
            ?? BrowserSoftwareUpdateChannel.named(
                Bundle.main.object(
                    forInfoDictionaryKey: Self.defaultChannelInfoKey
                ) as? String ?? ""
            )
            ?? .stable
        // A preference every earlier launch wrote, read before this launch
        // writes it.
        let ranBefore = preferences?.string(forKey: Self.bundledChannelPreferenceKey) != nil
        let channel = Self.launchChannel(
            bundledDefault: bundledDefaultChannel,
            preferences: preferences
        )
        let widgetSource = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: widgetSource)
        let userDriver = BrowserSoftwareUpdateUserDriver(
            model: model,
            channel: channel,
            feedURLOverride: feedURLOverride,
            localFeedURL: { Self.localFeedURL(in: preferences) }
        )
        self.model = model
        self.widgetSource = widgetSource
        let idleRestart = BrowserIdleRestart(model: model, preferences: preferences)
        self.idleRestart = idleRestart
        restartsWhenIdle = idleRestart.isEnabled
        self.isEnabled = isEnabled
        self.preferences = preferences
        self.channel = channel
        self.userDriver = userDriver
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: userDriver
        )
        let refreshCoordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        self.updater = updater
        self.refreshCoordinator = refreshCoordinator
        localFeedURL = Self.localFeedURL(in: preferences)
        rollback = BrowserSoftwareUpdateRollback(
            preferences: preferences,
            feedURL: { [weak updater] in updater?.feedURL },
            allowedChannels: { [weak userDriver] in userDriver?.channel.allowedSparkleChannels ?? [] })
        userDriver.updateCycleDidFinish = { [weak refreshCoordinator] in
            refreshCoordinator?.updateCycleDidFinish()
        }
        userDriver.updateWasFound = { [weak refreshCoordinator] in
            refreshCoordinator?.updateWasFound()
        }
        model.reminderChanged = { [weak self] date in self?.keepReminder(until: date) }
        if let date = preferences?.object(forKey: Self.reminderPreferenceKey) as? Date {
            model.restoreReminder(until: date)
            if model.remindAfter != nil { keepReminder(until: date) }
        }

        observeAutomaticPreferences()
        guard isEnabled else { return }
        if let preferences,
            let whatsNew = BrowserSoftwareUpdateWhatsNew.recordLaunch(preferences: preferences, ranBefore: ranBefore)
        {
            // An update made a reminder about the version before it moot.
            model.reveal()
            model.presentWhatsNew(
                version: whatsNew.version, build: whatsNew.build, highlights: whatsNew.highlights,
                releaseNotes: whatsNew.releaseNotes)
        }
        startUpdater()
    }

    /// The updater `environment`'s launch runs: off under tests, off in a
    /// development build, which must never install a release over itself, and
    /// off in an isolated launch unless it names a loopback test feed, which
    /// it then checks on the development channel with preferences kept apart
    /// from the installed app's.
    static func forLaunch(
        _ environment: BrowserLaunchEnvironment, isRelease: Bool = ProductIdentity.isRelease
    ) -> BrowserSoftwareUpdateService {
        let isolatedFeed = environment.isolatedSoftwareUpdateFeedURL
        let service = BrowserSoftwareUpdateService(
            isEnabled: environment.presentsInstalledApplicationUI
                && ((isRelease && !environment.requiresIsolation) || isolatedFeed != nil),
            preferences: environment.requiresIsolation ? nil : .standard,
            defaultChannel: isolatedFeed.map { _ in .development },
            feedURLOverride: isolatedFeed
        )
        if environment.requiresIsolation, let fixture = environment.softwareUpdateWidgetFixture {
            service.presentIsolatedSidebarWidgetFixture(fixture)
        }
        return service
    }

    // MARK: - Actions - Checking

    /// A check the person asked for, which also brings back a card they hid.
    func checkForUpdates() {
        guard isEnabled else {
            model.presentError(
                message: "Update checks are off in this copy of Ode.",
                acknowledgement: {}
            )
            return
        }
        model.reveal()
        refreshCoordinator.checkForUpdates()
    }

    func applicationDidBecomeActive() {
        localFeedURL = Self.localFeedURL(in: preferences)
        guard isEnabled else { return }
        refreshCoordinator.applicationDidBecomeActive()
    }

    // MARK: - Actions - Local feed

    /// Reads the hidden preference again, for Settings.
    func refreshLocalFeed() {
        localFeedURL = Self.localFeedURL(in: preferences)
    }

    /// Goes back to the published feed.
    func stopUsingLocalFeed() {
        preferences?.removeObject(forKey: Self.localFeedPreferenceKey)
        localFeedURL = nil
    }

    private static func localFeedURL(in preferences: UserDefaults?) -> URL? {
        BrowserLaunchEnvironment.loopbackSoftwareUpdateFeedURL(preferences?.string(forKey: localFeedPreferenceKey))
    }

    // MARK: - Actions - Going back

    /// Whether Ode can go back to an earlier version now: not while Sparkle
    /// downloads or holds an update to install at quit, which would race the
    /// swap.
    var canGoBack: Bool {
        isEnabled && rollback.unavailableReason == nil
            && ![.downloading, .extracting, .readyToInstall, .installing].contains(model.phase)
    }

    /// Ode's quit was allowed: going back, when asked for, starts its swap.
    func applicationWillQuit() {
        rollback.applicationWillQuit()
    }

    /// Ode was asked to quit and stayed open.
    func applicationStayedOpen() {
        model.applicationStayedOpen()
        rollback.applicationStayedOpen()
    }

    /// The last launch did not finish starting: with automatic checks on, a
    /// fixed version is looked for now rather than after the hour between
    /// checks, and with automatic downloads it is staged before the engine
    /// loads. With checks off, nothing contacts the feed.
    func checkAfterFailedStart() {
        guard isEnabled else { return }
        refreshCoordinator.checkAfterFailedStart()
    }

    // MARK: - Actions - Fixtures

    /// Presents updater states for an explicitly isolated verification launch.
    /// It never starts Sparkle or reads an appcast, and is deliberately absent
    /// from the production launch path.
    func presentIsolatedSidebarWidgetFixture(_ description: String) {
        guard !isEnabled else { return }
        let components = description.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: true
        ).map(String.init)
        let fixture = BrowserSoftwareUpdateFixture.named(components.first ?? "available")
        let version = components.count > 1 ? components[1] : "0.5.99"
        let build = components.count > 2 ? components[2] : "599"
        let releaseNotes = """
            ## What's New

            - Software update progress stays visible in the sidebar.
            - Release notes open only when you ask to review them.
            """
        model.presentUpdate(
            title: "Ode \(version)",
            version: version,
            build: build,
            releaseNotes: releaseNotes,
            isInformationOnly: false,
            isFixture: true,
            install: {},
            skip: {}
        )
        fixture.present(on: model, version: version, build: build, releaseNotes: releaseNotes)
    }

    // MARK: - Actions - Launch

    private func startUpdater() {
        do {
            try updater.start()
            startErrorDescription = nil
            refreshCoordinator.updaterDidStart()
        } catch {
            isEnabled = false
            startErrorDescription = error.localizedDescription
            model.presentError(
                message: "Ode could not start software updates: \(error.localizedDescription)",
                acknowledgement: {}
            )
        }
    }

    private static func launchChannel(
        bundledDefault: BrowserSoftwareUpdateChannel,
        preferences: UserDefaults?
    ) -> BrowserSoftwareUpdateChannel {
        let previousBundledChannel = preferences?.string(
            forKey: bundledChannelPreferenceKey
        )
        guard previousBundledChannel == bundledDefault.name else {
            preferences?.set(
                bundledDefault.name,
                forKey: bundledChannelPreferenceKey
            )
            preferences?.set(
                bundledDefault.name,
                forKey: channelPreferenceKey
            )
            return bundledDefault
        }
        return BrowserSoftwareUpdateChannel.named(
            preferences?.string(
                forKey: channelPreferenceKey
            ) ?? ""
        ) ?? bundledDefault
    }

    /// Keeps "Remind me tomorrow" for the next launch, and brings the card
    /// back when the day has passed while Ode runs.
    private func keepReminder(until date: Date?) {
        preferences?.set(date, forKey: Self.reminderPreferenceKey)
        reminder?.cancel()
        reminder = nil
        guard let date else { return }
        reminder = Task { @MainActor [weak model] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            model?.reminderDue()
        }
    }

    // MARK: - Actions - Automatic preferences

    /// Sparkle's KVO changes also invalidate SwiftUI when Sparkle or Settings changes a preference.
    private func observeAutomaticPreferences() {
        automaticPreferenceObservations = [
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.automaticPreferencesDidChange() }
            },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.automaticPreferencesDidChange() }
            },
        ]
    }

    private func automaticPreferencesDidChange() {
        automaticPreferenceRevision &+= 1
    }

    // MARK: - Mutators

    /// Off stops future automatic downloads, preserving checks and any already prepared install.
    /// Idle restarts remain a separate opt-in and are never changed by this control.
    func setAutomaticUpdates(_ isEnabled: Bool) {
        if isEnabled { setAutomaticallyChecksForUpdates(true) }
        setAutomaticallyDownloadsUpdates(isEnabled)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        if model.isFixture {
            fixtureAutomaticallyChecks = isEnabled
        } else {
            updater.automaticallyChecksForUpdates = isEnabled
            automaticPreferencesDidChange()
        }
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        if model.isFixture {
            fixtureAutomaticallyDownloads = isEnabled
        } else {
            updater.automaticallyDownloadsUpdates = isEnabled
            automaticPreferencesDidChange()
        }
    }
}
