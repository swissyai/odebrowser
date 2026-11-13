import Foundation

/// What a launch does before it builds the browser, from the launches the
/// record keeps: start normally, ask whether to start in safe mode, or offer
/// recovery. Every choice is made before any engine loads.
enum BrowserLaunchSafetyDecision: Equatable, Sendable {
    /// Start as usual; when the last launch did not finish starting, look for
    /// a fixed version at once.
    case start(checksForFix: Bool)
    /// Ask whether to start in safe mode: after `failedStarts` launches in a
    /// row did not finish starting, or because Shift was held.
    case askSafeStart(failedStarts: Int, askedWithShift: Bool)
    /// Safe mode has not helped, or many starts failed: offer an update, safe
    /// mode once more and quitting, and load no engine until the person picks.
    case recover(failedStarts: Int, safeModeFailed: Bool)
}

enum BrowserLaunchSafety {
    // MARK: - Static Variables

    /// Failed starts in a row before a launch asks about safe mode.
    static let askingStreak = 2
    /// Failed starts in a row before a launch offers recovery instead.
    static let recoveringStreak = 4
    /// Silences every launch prompt, for automation and tests.
    static let suppressingKey = "ODE_SUPPRESS_LAUNCH_PROMPTS"
    /// Lets an isolated launch ask, for the end-to-end runs that drive it.
    static let isolatedPromptsKey = "ODE_LAUNCH_SAFETY_PROMPTS"

    // MARK: - Actions - Deciding

    static func decide(
        failedStarts: Int, safeModeFailed: Bool, shiftHeld: Bool, promptsAllowed: Bool
    ) -> BrowserLaunchSafetyDecision {
        guard promptsAllowed else { return .start(checksForFix: failedStarts > 0) }
        if safeModeFailed || failedStarts >= recoveringStreak {
            return .recover(failedStarts: failedStarts, safeModeFailed: safeModeFailed)
        }
        if failedStarts >= askingStreak || shiftHeld {
            return .askSafeStart(failedStarts: failedStarts, askedWithShift: shiftHeld && failedStarts < askingStreak)
        }
        return .start(checksForFix: failedStarts > 0)
    }

    /// Whether this launch may ask anything before it starts: never under
    /// tests, in a launch without the app's own interface, or when silenced,
    /// and in an isolated launch only when asked to.
    static func promptsAllowed(_ environment: BrowserLaunchEnvironment, values: [String: String]) -> Bool {
        guard !environment.isXCTestRuntime, environment.presentsInstalledApplicationUI,
            values[suppressingKey] != "1"
        else { return false }
        return !environment.requiresIsolation || values[isolatedPromptsKey] == "1"
    }
}

/// One launch in safe mode: what it leaves off so a crash it caused cannot
/// recur, all for this launch only. Nothing stored changes: no setting is
/// rewritten, no extension removed, no data deleted.
struct BrowserSafeMode: Equatable, Sendable {
    struct Controls: OptionSet, Hashable, Sendable {
        let rawValue: Int

        /// Each window opens on its start page, and a tab loads its page only
        /// when the person opens it.
        static let pagesWaitUntilOpened = Self(rawValue: 1 << 0)
        static let syncPaused = Self(rawValue: 1 << 1)
        /// Needs the engine to start without extensions.
        static let extensionsOff = Self(rawValue: 1 << 2)
        /// Needs the engine to start without its GPU process.
        static let graphicsAccelerationOff = Self(rawValue: 1 << 3)
    }

    /// What the app can leave off by itself today. Extensions and graphics
    /// acceleration need switches the engine reads as it starts.
    static let available: Controls = [.pagesWaitUntilOpened, .syncPaused]

    let controls: Controls

    init(controls: Controls = Self.available) {
        self.controls = controls
    }

    /// What safe mode offers, as the safe start window says it.
    var offer: String {
        var parts: [String] = []
        if controls.contains(.extensionsOff) { parts.append(String(localized: "without extensions")) }
        if controls.contains(.syncPaused) { parts.append(String(localized: "with sync paused")) }
        if controls.contains(.graphicsAccelerationOff) {
            parts.append(String(localized: "with graphics acceleration off"))
        }
        if controls.contains(.pagesWaitUntilOpened) {
            parts.append(String(localized: "with pages loading only when you open them"))
        }
        let list = parts.formatted(.list(type: .and))
        return String(localized: "You can start \(list). Nothing is deleted or changed.")
    }

    /// What is off, as the banner in each window says it.
    var banner: String {
        var off: [String] = []
        if controls.contains(.extensionsOff) { off.append(String(localized: "extensions")) }
        if controls.contains(.syncPaused) { off.append(String(localized: "sync")) }
        if controls.contains(.graphicsAccelerationOff) { off.append(String(localized: "graphics acceleration")) }
        let pages = controls.contains(.pagesWaitUntilOpened)
        switch (off.isEmpty, pages) {
        case (true, true):
            return String(localized: "Safe mode: pages load when you open them.")
        case (true, false):
            return String(localized: "Safe mode is on.")
        case (false, true):
            let list = off.formatted(.list(type: .and))
            return off.count == 1
                ? String(localized: "Safe mode: \(list) is off, and pages load when you open them.")
                : String(localized: "Safe mode: \(list) are off, and pages load when you open them.")
        case (false, false):
            let list = off.formatted(.list(type: .and))
            return off.count == 1
                ? String(localized: "Safe mode: \(list) is off.") : String(localized: "Safe mode: \(list) are off.")
        }
    }
}
