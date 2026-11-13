import Foundation

/// When the Space bar previews the finished download under the pointer: only
/// once the pointer has moved over its row since the last key press, so typing
/// into a page with the pointer resting on a row still types, and never while
/// a text field has the keyboard.
struct BrowserDownloadHoverPreview {
    // MARK: - Variables

    /// The finished file whose row the pointer is over.
    private(set) var fileURL: URL?
    private var movedAt: TimeInterval = -.infinity
    private var lastKeyAt: TimeInterval = -.infinity

    // MARK: - Actions - Pointer

    mutating func pointerMoved(over fileURL: URL, at time: TimeInterval) {
        self.fileURL = fileURL
        movedAt = time
    }

    mutating func pointerLeft(_ fileURL: URL) {
        guard self.fileURL == fileURL else { return }
        self.fileURL = nil
    }

    // MARK: - Actions - Keys

    /// Records a key press at `time`, on the clock the pointer's times use,
    /// and answers the file a press of the Space bar previews, if any.
    mutating func keyPressed(at time: TimeInterval, isSpace: Bool, isEditingText: Bool) -> URL? {
        defer { lastKeyAt = time }
        guard isSpace, !isEditingText, let fileURL, movedAt > lastKeyAt else { return nil }
        return fileURL
    }
}
