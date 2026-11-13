import Quartz

/// The Quick Look panel looks along the responder chain for what to show;
/// the application's delegate, at its end, hands it a download's file.
extension OdeAppDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        BrowserMacDownloadQuickLook.shared.hasPreview
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        BrowserMacDownloadQuickLook.shared.take(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        BrowserMacDownloadQuickLook.shared.release(panel)
    }
}
