import SwiftUI

/// What the windowed shell adds to a download's row: a finished file drags
/// straight out into Finder or another app, and the Space bar shows it in
/// Quick Look while the pointer rests on its row.
struct BrowserPlatformDownloadRowInteractions: ViewModifier {
    let download: DownloadState

    func body(content: Content) -> some View {
        if let fileURL = download.savedFileURL() {
            content
                .onDrag {
                    BrowserDownloadFileTransfer.dragItem(for: fileURL)
                } preview: {
                    BrowserDownloadDragPreview(fileURL: fileURL)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active: BrowserMacDownloadQuickLook.shared.pointerMoved(over: fileURL)
                    case .ended: BrowserMacDownloadQuickLook.shared.pointerLeft(fileURL)
                    }
                }
        } else {
            content
        }
    }
}
