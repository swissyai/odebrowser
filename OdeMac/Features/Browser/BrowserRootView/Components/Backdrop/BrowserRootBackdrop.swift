import SwiftUI

struct BrowserRootBackdrop: View {
    // MARK: - Variables

    let space: SpaceModel?
    let spaces: [SpaceModel]

    // MARK: - Actions - Presentation

    var body: some View {
        // Preserve coverage while colors change. Replacing this whole layer for
        // a Space ID briefly exposes the window background during a fade.
        // One calm Space ground spans the window, so docked chrome and the
        // gaps around the page share the same gradient and texture coordinates.
        SpaceBackdropBlend(spaces: spaces, selectedSpace: space) {
            BrowserWindowAtmosphere(space: $0)
        }
        // The window's background, wherever no page or control covers it, is
        // chrome: the title bar strip above a page and the gaps around it.
        .overlay { BrowserWindowTitleBarSurface() }
        .ignoresSafeArea()
    }
}
