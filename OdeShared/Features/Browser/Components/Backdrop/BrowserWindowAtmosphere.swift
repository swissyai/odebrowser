import SwiftUI

struct BrowserWindowAtmosphere: View {
    // MARK: - Variables

    /// The Space the window shows, or nil for none.
    let space: SpaceModel?
    /// Which of the Space's grounds it shows: the calm one by default, or
    /// the vivid ring around a window's page.
    var surface = SpaceGroundSurface.window

    /// The Space's look, read in `body` so it follows the Space's colors.
    private var branding: SpaceBranding? {
        space.map(\.settings.look)
    }

    var body: some View {
        ZStack {
            OdeColor.windowBackground
            if let branding {
                BrowserSpaceBannerBackground(branding: branding, surface: surface)
            }
        }
        .accessibilityHidden(true)
    }
}
