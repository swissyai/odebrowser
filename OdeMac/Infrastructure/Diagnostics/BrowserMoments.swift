import AppKit
import os

/// This launch's ``BrowserMomentLedger``: every moment Ode times is recorded
/// here, on the clock of system uptime, and emitted as a signpost so
/// Instruments shows it in any build. The ledger is read from beside the
/// session when the launch opens it and written back there a while after a
/// moment and at a quit; it is never sent anywhere.
@MainActor
final class BrowserMoments {
    // MARK: - Types

    /// A moment begun or recorded lately: its kind and tags, when it began
    /// and, once over, when it ended, on ``now``'s clock.
    struct Activity: Equatable {
        let kind: BrowserMomentLedger.Kind
        let tags: BrowserMomentLedger.Tags
        let began: UInt64
        let ended: UInt64?
    }

    // MARK: - Static Variables

    static let shared = BrowserMoments()
    /// How long after a moment the ledger waits before writing itself, so a
    /// run of moments costs one write.
    private static let saveDelay: Duration = .seconds(30)
    /// An input event further back than this when a moment begins did not
    /// start it.
    private static let inputReach: UInt64 = 500_000_000
    /// Core Animation commits at order 2,000,000 before the main run loop waits.
    private static let afterCoreAnimationCommit: CFIndex = 2_000_001
    /// How long after Return in the Command Bar a navigation still counts as
    /// the one it started.
    static let returnReach: Duration = .seconds(2)
    /// How long a moment begun and never ended still counts as in flight.
    static let flightReach: UInt64 = 10_000_000_000
    /// The recent moments kept to tell which one a hang fell in.
    private static let activitiesKept = 16
    /// The events a person starts a moment with.
    private static let inputEvents: Set<NSEvent.EventType> = [
        .keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .otherMouseUp, .swipe,
    ]

    // MARK: - Variables

    private(set) var ledger = BrowserMomentLedger()
    /// The moments begun and not yet ended, by kind: when and with what tags.
    private var started: [BrowserMomentLedger.Kind: (at: UInt64, tags: BrowserMomentLedger.Tags)] = [:]
    /// The latest moments begun or recorded, oldest first, hangs aside.
    private(set) var activities: [Activity] = []
    /// Where the ledger is kept, once a launch with a session on disk opened it.
    private var directory: URL?
    private var pendingSave: Task<Void, Never>?
    let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.odebrowser.ode", category: "Moments")

    // MARK: - Actions - Clock

    /// Now, in nanoseconds of system uptime: the clock every moment is timed on.
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// When the input AppKit is handling happened: a key press, a click or a
    /// swipe within ``inputReach`` of now, which starts the moment it asks
    /// for, so its wait in the event queue counts; otherwise now.
    static func inputTime(_ event: NSEvent? = NSApp.currentEvent, now: UInt64 = now) -> UInt64 {
        guard let event, inputEvents.contains(event.type), event.timestamp > 0 else { return now }
        let happened = UInt64(event.timestamp * 1_000_000_000)
        return happened <= now && now - happened <= inputReach ? happened : now
    }

    /// When this process started, on ``now``'s clock: before the dynamic
    /// loader ran, so a launch counts from the moment it was asked for. Nil
    /// when the system does not say.
    static func processStart(now: UInt64 = now, wallClock: Date = Date()) -> UInt64? {
        guard let started = processStartDate() else { return nil }
        let since = wallClock.timeIntervalSince(started)
        guard since >= 0, UInt64(since * 1_000_000_000) <= now else { return nil }
        return now - UInt64(since * 1_000_000_000)
    }

    /// The kernel's process start, kept with the PID so crash intake can
    /// distinguish process generations without relying on launch work timing.
    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }

    /// When the Mac last started, as a date.
    static var bootDate: Date? {
        var booted = timeval()
        var size = MemoryLayout<timeval>.stride
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&name, 2, &booted, &size, nil, 0) == 0, booted.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(booted.tv_sec) + Double(booted.tv_usec) / 1_000_000)
    }

    // MARK: - Actions - Recording

    /// Records a moment of `kind` from `start` to `end`, both on ``now``'s
    /// clock. An end before the start records nothing.
    func record(
        _ kind: BrowserMomentLedger.Kind, from start: UInt64, to end: UInt64 = now,
        tags: BrowserMomentLedger.Tags = .init()
    ) {
        guard end >= start else { return }
        let milliseconds = Double(end - start) / 1_000_000
        ledger.record(kind, milliseconds: milliseconds, tags: tags)
        note(Activity(kind: kind, tags: tags, began: start, ended: end))
        signposter.emitEvent("Moment", "\(kind.rawValue, privacy: .public) \(milliseconds, privacy: .public) ms")
        saveSoon()
    }

    /// Records a moment of `kind` that took `milliseconds`, measured elsewhere.
    func record(
        _ kind: BrowserMomentLedger.Kind, milliseconds: Double, tags: BrowserMomentLedger.Tags = .init()
    ) {
        ledger.record(kind, milliseconds: milliseconds, tags: tags)
        if milliseconds.isFinite, milliseconds >= 0 {
            let end = Self.now
            note(Activity(kind: kind, tags: tags, began: end - min(end, UInt64(milliseconds * 1_000_000)), ended: end))
        }
        signposter.emitEvent("Moment", "\(kind.rawValue, privacy: .public) \(milliseconds, privacy: .public) ms")
        saveSoon()
    }

    func count(_ counter: BrowserMomentLedger.Counter, by amount: Int = 1) {
        ledger.count(counter, by: amount)
        if amount > 0 {
            signposter.emitEvent(
                "Moment", "\(counter.kind.rawValue, privacy: .public).\(counter.name, privacy: .public) +\(amount)")
        }
        saveSoon()
    }

    /// Starts again from an empty ledger, for a harness run that measures
    /// from a known point.
    func reset() {
        ledger = BrowserMomentLedger()
        started = [:]
        activities = []
        saveSoon()
    }

    // MARK: - Actions - Hangs

    /// The moment in flight during a hang from `start` to `end`: the one
    /// begun last before the hang ended that had not ended before it began,
    /// a moment never ended counting for ``flightReach``. Nil for none.
    func moment(inFlightFrom start: UInt64, to end: UInt64) -> Activity? {
        activities.last { $0.began <= end && ($0.ended ?? $0.began + Self.flightReach) >= start }
    }

    /// Records a main-thread hang that began at `date`, from `start` to `end`
    /// on ``now``'s clock, tagged with the moment in flight, and logs it.
    func recordHang(at date: Date, from start: UInt64, to end: UInt64) {
        guard end >= start else { return }
        let milliseconds = Double(end - start) / 1_000_000
        let during = moment(inFlightFrom: start, to: end)
        var tags = during?.tags ?? .init()
        tags.during = during?.kind.rawValue
        DiagnosticLog.hangs.notice(Self.hangLine(at: date, milliseconds: milliseconds, tags: tags))
        record(.hang, milliseconds: milliseconds, tags: tags)
    }

    /// How the log names a hang: when it began, how long it lasted and the
    /// moment in flight with its tags.
    static func hangLine(at date: Date, milliseconds: Double, tags: BrowserMomentLedger.Tags) -> String {
        let began = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let lasted = "The main thread hung for \(Int(milliseconds.rounded())) ms from \(began)"
        guard let during = tags.during else { return lasted + " with no moment in flight" }
        let others = tags.labels.filter { !$0.hasPrefix("during=") }
        return lasted + " during \(during)" + (others.isEmpty ? "" : " (\(others.joined(separator: ", ")))")
    }

    /// Keeps `activity` as the latest: a moment of its kind in flight is over
    /// or starts again, so it takes that one's place.
    private func note(_ activity: Activity) {
        guard activity.kind != .hang else { return }
        activities.removeAll { $0.kind == activity.kind && $0.ended == nil }
        activities.append(activity)
        if activities.count > Self.activitiesKept { activities.removeFirst(activities.count - Self.activitiesKept) }
    }

    // MARK: - Actions - Spans

    /// Starts a moment of `kind` at `start`, which `end` finishes; a moment
    /// of the kind already started starts again.
    func begin(
        _ kind: BrowserMomentLedger.Kind, at start: UInt64 = inputTime(), tags: BrowserMomentLedger.Tags = .init()
    ) {
        started[kind] = (start, tags)
        began(kind, at: start, tags: tags)
    }

    /// A moment of `kind` that something else times began at `start`, so a
    /// hang before it is recorded falls in it.
    func began(_ kind: BrowserMomentLedger.Kind, at start: UInt64, tags: BrowserMomentLedger.Tags = .init()) {
        note(Activity(kind: kind, tags: tags, began: start, ended: nil))
    }

    /// Finishes the moment of `kind` begun within `reach` before `end`,
    /// recording it; one begun longer ago did not lead here and is dropped.
    func end(_ kind: BrowserMomentLedger.Kind, at end: UInt64 = now, within reach: Duration = .seconds(10)) {
        guard let (start, tags) = started.removeValue(forKey: kind), end >= start,
            end - start <= UInt64(reach.components.seconds) * 1_000_000_000
        else { return }
        record(kind, from: start, to: end, tags: tags)
    }

    /// Finishes the moment of `kind` once the frame being built now is
    /// committed.
    func endAtNextCommit(_ kind: BrowserMomentLedger.Kind) {
        afterNextCommit { [weak self] in self?.end(kind) }
    }

    /// Runs `body` once, just after Core Animation commits the frame being
    /// built now, as the main run loop goes to wait.
    func afterNextCommit(_ body: @escaping @MainActor () -> Void) {
        let committed = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Self.afterCoreAnimationCommit
        ) { _, _ in
            MainActor.assumeIsolated { body() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), committed, .commonModes)
    }

    // MARK: - Actions - Files

    /// Takes up the ledger kept beside the session in `directory`, adding
    /// what this launch recorded before.
    func open(in directory: URL) {
        guard self.directory == nil else { return }
        self.directory = directory
        let recorded = ledger
        ledger = BrowserMomentLedger.read(in: directory)
        for (name, entry) in recorded.moments {
            let kind = BrowserMomentLedger.Kind(rawValue: name)
            for sample in entry.recent { ledger.record(kind, milliseconds: sample.milliseconds, tags: sample.tags) }
            for (counter, value) in entry.counters {
                ledger.count(BrowserMomentLedger.Counter(name: counter, kind: kind), by: value)
            }
        }
        if !recorded.moments.isEmpty { saveSoon() }
    }

    /// Writes the ledger now, as a quit does.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let directory, let data = ledger.encoded() else { return }
        BrowserMomentLedger.write(data, in: directory)
    }

    private func saveSoon() {
        guard directory != nil, pendingSave == nil else { return }
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingSave = nil
            guard let directory = self.directory, let data = self.ledger.encoded() else { return }
            await Task.detached(priority: .utility) { BrowserMomentLedger.write(data, in: directory) }.value
        }
    }
}
