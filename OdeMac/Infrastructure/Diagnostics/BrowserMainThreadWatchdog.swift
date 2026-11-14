import AppKit
import Foundation

/// Measures how long Ode's main thread takes to run a small block, from a
/// thread of its own, once a second while Ode is the active app: a block that
/// waits ``BrowserHangLog/recorded`` or more is a hang, and `record` hears
/// when it began and how long it lasted. It reads no page and samples no
/// stack; it only times the main thread.
final class BrowserMainThreadWatchdog: @unchecked Sendable {
    // MARK: - Variables

    private let record: @Sendable (Date, TimeInterval) -> Void
    private let interval: TimeInterval
    private let followsActivation: Bool
    private let lock = NSLock()
    private var running = false
    private var paused = false
    private var thread: Thread?
    private var observers: [any NSObjectProtocol] = []

    // MARK: - Initializers

    /// `followsActivation` pauses the watch while Ode is not the active app.
    init(
        interval: TimeInterval = 1, followsActivation: Bool = true,
        record: @escaping @Sendable (Date, TimeInterval) -> Void
    ) {
        self.interval = interval
        self.followsActivation = followsActivation
        self.record = record
    }

    deinit { stop() }

    // MARK: - Actions - Running

    /// Starts watching, paused while Ode is not the active app.
    @MainActor
    func start() {
        let started: Bool = lock.withLock {
            guard !running else { return false }
            running = true
            paused = followsActivation && !NSApp.isActive
            return true
        }
        guard started else { return }
        let center = NotificationCenter.default
        if followsActivation {
            observers = [
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) {
                    [weak self] _ in self?.setPaused(false)
                },
                center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) {
                    [weak self] _ in self?.setPaused(true)
                },
            ]
        }
        let thread = Thread { [weak self] in self?.watch() }
        thread.name = "Ode main thread watchdog"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        lock.withLock { running = false }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func setPaused(_ paused: Bool) {
        lock.withLock { self.paused = paused }
    }

    private func watch() {
        while lock.withLock({ running }) {
            Thread.sleep(forTimeInterval: interval)
            guard lock.withLock({ running && !paused }) else { continue }
            let sent = Date()
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { answered.signal() }
            answered.wait()
            let waited = Date().timeIntervalSince(sent)
            if waited >= BrowserHangLog.recorded { record(sent, waited) }
        }
    }
}
