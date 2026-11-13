import SwiftUI

/// The sample page at the chosen default zoom, for the Page card when the pane
/// has no pinned window crop to show it in.
struct BrowserLookAndFeelPagePreview: View {
    private(set) var pageZoom = BrowserDefaultPageZoomStore.shared

    var body: some View {
        BrowserSettingsPagePreview(zoom: pageZoom.defaultZoom)
            .clipShape(.rect(cornerRadius: OdeRadius.compact, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OdeRadius.compact, style: .continuous)
                    .strokeBorder(.primary.opacity(OdeOpacity.border))
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("default-page-zoom-preview")
    }
}
