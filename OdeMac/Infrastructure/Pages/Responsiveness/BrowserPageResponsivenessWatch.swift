import AppKit
import Observation

/// Watches whether one page answers the person, through
/// ``BrowserPageResponsiveness``: each interaction asks the page's document a
/// trivial question when none is out, and while one is out the watch checks
/// once a second whether the page is frozen. The page's window shows the
/// frozen page's bar and the sidebar its mark from `isFrozen`.
@MainActor @Observable
final class BrowserPageResponsivenessWatch {
    // MARK: - Static Variables

    /// When the Mac last woke from sleep, which the watches all read.
    @ObservationIgnored private(set) static var lastWake: Date?
    @ObservationIgnored private static var wakeObserver: (any NSObjectProtocol)?

    // MARK: - Variables

    /// Whether the window offers to wait or stop the page now.
    private(set) var isFrozen = false
    @ObservationIgnored private var state = BrowserPageResponsiveness()
    @ObservationIgnored private let ask: @MainActor () async -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var checking: Task<Void, Never>?

    // MARK: - Initializers

    /// `ask` puts the trivial question to the page's document and returns
    /// once the document answered, or at once when there is no document to
    /// ask.
    init(ask: @escaping @MainActor () async -> Void, now: @escaping @MainActor () -> Date = { Date() }) {
        self.ask = ask
        self.now = now
        Self.observeWake()
    }

    // MARK: - Actions - Watching

    /// The person clicked in the page or typed into it.
    func interacted() {
        if let question = state.interacted(at: now()) {
            Task { @MainActor [weak self, ask] in
                await ask()
                self?.answered(question)
            }
        }
        startChecking()
    }

    /// The page left the screen.
    func hidden() {
        state.hidden()
        refresh()
    }

    /// The person chose to wait.
    func wait() {
        state.wait(at: now())
        refresh()
    }

    /// The page was stopped.
    func reset() {
        state.reset()
        refresh()
    }

    /// Reads the state again, as the checking loop does each second.
    func refresh() {
        let frozen = state.isFrozen(at: now(), lastWake: Self.lastWake)
        if frozen != isFrozen { isFrozen = frozen }
        if state.question == nil {
            checking?.cancel()
            checking = nil
        }
    }

    private func answered(_ question: Int) {
        state.answered(question)
        refresh()
    }

    private func startChecking() {
        guard checking == nil, state.question != nil else { return }
        checking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    // MARK: - Actions - Waking

    private static func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { lastWake = Date() }
        }
    }
}
