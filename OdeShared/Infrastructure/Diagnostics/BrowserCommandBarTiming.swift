import Foundation
import os

/// Marks along the Command Bar's open path: as signposts, so Instruments can
/// time an open in any build, and to a test harness when one listens.
@MainActor
enum BrowserCommandBarTiming {
    /// A moment in one open of the Command Bar.
    enum Mark: String, Sendable, CaseIterable {
        /// The New Tab command or a menu asked for the bar.
        case command
        /// The bar's model holds its resting rows.
        case modelReady
        /// The bar's field entered the window.
        case fieldInWindow
        /// The field holds the keyboard.
        case focused
        /// The frame that first shows the field was committed.
        case frameCommitted
        /// The bar closed.
        case closed
    }

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.odebrowser.ode", category: "CommandBar")

    /// Hears each mark with the uptime it happened at, in nanoseconds; set
    /// only by a test harness.
    static var observer: ((Mark, UInt64) -> Void)?

    static func mark(_ mark: Mark) {
        signposter.emitEvent("CommandBar", "\(mark.rawValue, privacy: .public)")
        observer?(mark, DispatchTime.now().uptimeNanoseconds)
    }

    /// Marks the commit of the frame being built now: once, just after Core
    /// Animation commits it as the main run loop goes to wait, without
    /// waiting for its animations to finish.
    static func markWhenCommitted(_ mark: Mark) {
        guard observer != nil else { return }
        let committed = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Self.afterCoreAnimationCommit
        ) { _, _ in
            MainActor.assumeIsolated { Self.mark(mark) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), committed, .commonModes)
    }

    /// Core Animation commits at order 2,000,000 before the main run loop waits.
    private static let afterCoreAnimationCommit: CFIndex = 2_000_001
}
