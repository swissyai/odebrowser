import CoreGraphics
import Foundation

/// Restarts Ode to finish installing a downloaded update while the Mac is
/// idle, when the person turned that on: after five minutes without keyboard
/// or mouse input, and never while something a restart would interrupt is
/// under way. The application names those activities in `blockers`: a
/// download in progress and media playing today; a call or a screen recording
/// can join them as the app learns to see them.
@MainActor
final class BrowserIdleRestart {
    // MARK: - Static Variables

    static let idleThreshold: TimeInterval = 5 * 60
    static let checkInterval: Duration = .seconds(60)
    static let preferenceKey = "ode.software-update.restart-when-idle"

    // MARK: - Variables

    var isEnabled: Bool {
        didSet {
            preferences?.set(isEnabled, forKey: Self.preferenceKey)
            schedule()
        }
    }
    /// Each answers whether a restart now would interrupt something.
    var blockers: [@MainActor () -> Bool] = []

    private let model: BrowserSoftwareUpdateModel
    private let preferences: UserDefaults?
    private let idleSeconds: @MainActor () -> TimeInterval
    private var watch: Task<Void, Never>?

    // MARK: - Initializers

    init(
        model: BrowserSoftwareUpdateModel,
        preferences: UserDefaults?,
        idleSeconds: @escaping @MainActor () -> TimeInterval = BrowserIdleRestart.systemIdleSeconds
    ) {
        self.model = model
        self.preferences = preferences
        self.idleSeconds = idleSeconds
        isEnabled = preferences?.bool(forKey: Self.preferenceKey) ?? false
        schedule()
    }

    // MARK: - Actions - Restarting

    /// Restarts to install the update when every condition holds, and answers
    /// whether it did.
    @discardableResult
    func restartIfIdle() -> Bool {
        guard isEnabled, model.phase == .readyToInstall, model.snapshot.allowsInstallAndRelaunch,
            idleSeconds() >= Self.idleThreshold, !blockers.contains(where: { $0() })
        else { return false }
        DiagnosticLog.launch.notice("Restarting to install an update while this Mac is idle")
        model.installAndRelaunchNow()
        return true
    }

    private func schedule() {
        watch?.cancel()
        guard isEnabled else {
            watch = nil
            return
        }
        watch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                guard let self, !Task.isCancelled else { return }
                restartIfIdle()
            }
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad input in this login
    /// session.
    static func systemIdleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
