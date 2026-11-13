import Foundation
import Observation

/// The restore window's list of dated session copies and what restoring one
/// does. With the browser running the session is open, so Ode leaves a
/// request for its next launch and quits to open again; before the session
/// opens, the copy is put in place at once. Either way the core keeps the
/// session it replaces as a copy first, so the list can undo a restore.
@MainActor @Observable
final class BrowserRestoreCopiesModel {
    // MARK: - Types

    enum Timing: Equatable {
        /// The browser is running: Ode quits, restores the copy and opens again.
        case relaunch
        /// No session is open yet: the copy is restored at once.
        case now
    }

    /// What restoring needs from outside, which tests replace.
    struct Actions {
        var restoreNow: @MainActor (RecoveryCopy, URL) throws -> Void = { copy, directory in
            try BrowserRecoveryCopies.restore(copy, in: directory)
        }
        var requestRestore: @MainActor (RecoveryCopy, URL) -> Bool = { copy, directory in
            BrowserRecoveryCopies.requestRestore(copy, in: directory)
        }
        var relaunch: @MainActor () -> Void = { BrowserMacRelaunch.relaunchAfterQuit() }
    }

    // MARK: - Variables

    let directory: URL
    let timing: Timing
    private(set) var copies: [RecoveryCopy]
    /// The copy the list starts on: the one a launch held back, else the newest.
    private(set) var initialSelection: RecoveryCopy.ID?
    /// Why the last restore did not happen, as the window says it.
    private(set) var failure: String?
    /// Runs once a restore at once succeeded.
    var restored: (@MainActor (RecoveryCopy) -> Void)?
    private let actions: Actions

    // MARK: - Initializers

    init(directory: URL, timing: Timing, copies: [RecoveryCopy]? = nil, failure: String? = nil, actions: Actions = Actions()) {
        self.directory = directory
        self.timing = timing
        let listed = copies ?? BrowserRecoveryCopies.list(in: directory)
        self.copies = listed
        self.failure = failure
        self.actions = actions
        initialSelection = listed.first(where: \.held)?.id ?? listed.first?.id
    }

    // MARK: - Actions - Restoring

    /// Restores `copy` as `timing` says. Answers whether it went ahead.
    @discardableResult
    func restore(_ copy: RecoveryCopy) -> Bool {
        switch timing {
        case .relaunch:
            guard actions.requestRestore(copy, directory) else {
                failure = String(localized: "Ode couldn't save the request to restore that copy. Nothing was changed.")
                return false
            }
            failure = nil
            actions.relaunch()
            return true
        case .now:
            do {
                try actions.restoreNow(copy, directory)
            } catch {
                DiagnosticLog.launch.notice("A copy of the session could not be restored: \(DiagnosticLog.describe(error))")
                failure = String(localized: "That copy couldn't be restored. Nothing was changed.")
                copies = BrowserRecoveryCopies.list(in: directory)
                return false
            }
            failure = nil
            restored?(copy)
            return true
        }
    }

    /// The explanation above the list.
    var explanation: String {
        switch timing {
        case .relaunch:
            String(
                localized:
                    "Ode will quit, put the copy you choose in place and open again. Your current session is kept as a copy first, so you can come back to it."
            )
        case .now:
            String(
                localized:
                    "The copy you choose replaces the saved session. The current one is kept as a copy first, so you can come back to it."
            )
        }
    }
}
