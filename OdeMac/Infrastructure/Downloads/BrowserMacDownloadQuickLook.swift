import AppKit
import Quartz

/// Shows a finished download in the system's Quick Look panel: from its row's
/// menu, or with the Space bar while the pointer rests on its row. A second
/// press of the Space bar, or Escape, closes the panel.
@MainActor
final class BrowserMacDownloadQuickLook: NSObject {
    // MARK: - Static Variables

    static let shared = BrowserMacDownloadQuickLook()

    private nonisolated static let spaceKeyCode: UInt16 = 49

    // MARK: - Variables

    /// The file the panel shows, or shows once it opens.
    var fileURL: URL?
    private var hover = BrowserDownloadHoverPreview()
    private var keyMonitor: Any?

    // MARK: - Actions - Panel

    /// Shows `fileURL` in the panel, or closes the panel when it shows it.
    func toggle(_ fileURL: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, self.fileURL == fileURL {
            panel.orderOut(nil)
            return
        }
        self.fileURL = fileURL
        panel.updateController()
        // A shell whose responders do not hand the panel over still shows it.
        if panel.dataSource !== self { take(panel) }
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Whether the panel may show what this holds, as a responder asks.
    var hasPreview: Bool { fileURL != nil }

    func take(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func release(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    // MARK: - Actions - Pointer

    /// The pointer moved over the row of the finished file at `fileURL`.
    func pointerMoved(over fileURL: URL) {
        installKeyMonitor()
        hover.pointerMoved(over: fileURL, at: ProcessInfo.processInfo.systemUptime)
    }

    func pointerLeft(_ fileURL: URL) {
        hover.pointerLeft(fileURL)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let isSpace =
            event.keyCode == Self.spaceKeyCode
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        let isEditingText = NSApp.keyWindow?.firstResponder is NSText
        guard let fileURL = hover.keyPressed(at: event.timestamp, isSpace: isSpace, isEditingText: isEditingText)
        else { return event }
        toggle(fileURL)
        return nil
    }
}

extension BrowserMacDownloadQuickLook: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { fileURL == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let fileURL = MainActor.assumeIsolated { self.fileURL }
        return fileURL.map { $0 as NSURL }
    }

    /// The Space bar closes the panel it opened, as it does in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == Self.spaceKeyCode else { return false }
        MainActor.assumeIsolated { panel.orderOut(nil) }
        return true
    }
}
