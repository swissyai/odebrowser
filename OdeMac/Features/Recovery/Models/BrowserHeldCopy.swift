import Foundation
import Observation

/// The copy of the session a launch held back because the session it opened
/// had lost more than half of its Spaces or tabs without the person removing
/// them, while the person has not answered: restore that copy, or keep this
/// session. The core keeps the copy held across launches until then, so the
/// banner returns each launch.
@MainActor @Observable
final class BrowserHeldCopy {
    // MARK: - Variables

    private(set) var copy: RecoveryCopy?
    let directory: URL
    private let keep: @MainActor () -> Void
    private let showRestore: @MainActor (URL) -> Void

    // MARK: - Initializers

    /// Reads the copy held beside the session in `directory`, if any. `keep`
    /// tells the core the session is right; `showRestore` opens the restore
    /// window on the held copy.
    init(
        directory: URL, copies: [RecoveryCopy]? = nil,
        keep: @escaping @MainActor () -> Void,
        showRestore: @escaping @MainActor (URL) -> Void = { directory in
            BrowserMacRestoreWindow.show(directory: directory, timing: .relaunch)
        }
    ) {
        self.directory = directory
        self.keep = keep
        self.showRestore = showRestore
        copy = (copies ?? BrowserRecoveryCopies.list(in: directory)).first(where: \.held)
    }

    // MARK: - Actions - Answering

    /// The person keeps the session as it is: the held copy rotates out again.
    func keepThisSession() {
        guard copy != nil else { return }
        keep()
        copy = nil
    }

    /// The person wants the held copy back: the restore window opens on it.
    func restoreThatCopy() {
        guard copy != nil else { return }
        showRestore(directory)
    }

    /// What the banner says about the held copy.
    var message: String? {
        guard let copy else { return nil }
        return String(
            localized:
                "The copy from \(copy.taken) had \(copy.contents). If you didn't close them, you can restore that copy."
        )
    }
}
