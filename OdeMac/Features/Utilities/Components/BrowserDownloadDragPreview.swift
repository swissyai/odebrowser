import AppKit
import SwiftUI

/// What follows the pointer while a finished download is dragged out: the
/// file's own icon, as Finder shows it, above its name.
struct BrowserDownloadDragPreview: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: OdeSpacing.extraExtraSmall) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(verbatim: fileURL.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
        .padding(OdeSpacing.extraSmall)
    }
}
