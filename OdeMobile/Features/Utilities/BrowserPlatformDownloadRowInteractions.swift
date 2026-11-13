import SwiftUI

/// The compact shell hands files over through the share sheet and Files, so
/// a download's row adds nothing of its own.
struct BrowserPlatformDownloadRowInteractions: ViewModifier {
    let download: DownloadState

    func body(content: Content) -> some View {
        content
    }
}
