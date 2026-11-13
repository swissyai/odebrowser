import AppKit
import SwiftUI

/// The window that lists the dated copies of the session and restores one,
/// from the File menu, from the missing-tabs banner, and from the windows a
/// launch shows before the session opens. One shows at a time.
@MainActor
final class BrowserMacRestoreWindow: NSObject, NSWindowDelegate {
    // MARK: - Static Variables

    private static var shown: BrowserMacRestoreWindow?

    // MARK: - Variables

    private let window: NSWindow
    let model: BrowserRestoreCopiesModel

    // MARK: - Initializers

    private init(model: BrowserRestoreCopiesModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = String(localized: "Restore from an earlier copy")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        let content = NSHostingView(
            rootView: BrowserRestoreCopiesView(model: model, cancel: { [weak self] in self?.close() }))
        content.sizingOptions = [.preferredContentSize]
        window.contentView = content
    }

    // MARK: - Actions - Showing

    /// Shows the copies kept beside the session in `directory`, restoring as
    /// `timing` says. `failure` explains a restore an earlier launch could not
    /// make. `restored` runs once a restore at once succeeded.
    static func show(
        directory: URL, timing: BrowserRestoreCopiesModel.Timing, failure: String? = nil,
        restored: (@MainActor (RecoveryCopy) -> Void)? = nil
    ) {
        shown?.close()
        let model = BrowserRestoreCopiesModel(directory: directory, timing: timing, failure: failure)
        let controller = BrowserMacRestoreWindow(model: model)
        model.restored = { [weak controller] copy in
            controller?.close()
            restored?(copy)
        }
        shown = controller
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if Self.shown === self { Self.shown = nil }
    }
}
