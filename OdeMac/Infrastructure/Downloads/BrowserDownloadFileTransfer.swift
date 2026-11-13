import AppKit

/// Hands a finished download's file to other apps as Finder hands over a
/// file: as its file URL, so Finder copies it, and Mail, Messages or a page's
/// upload field take it as an attachment.
@MainActor
enum BrowserDownloadFileTransfer {
    // MARK: - Actions - Dragging

    /// What dragging the file at `fileURL` out of Ode carries.
    static func dragItem(for fileURL: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: fileURL as NSURL)
        provider.suggestedName = fileURL.lastPathComponent
        return provider
    }

    // MARK: - Actions - Copying

    /// Puts the file at `fileURL` on `pasteboard`, as Finder's Copy does.
    @discardableResult
    static func copy(_ fileURL: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([fileURL as NSURL])
    }
}
