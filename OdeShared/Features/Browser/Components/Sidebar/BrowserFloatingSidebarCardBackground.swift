import SwiftUI

/// The window's own Space color, one perceptual step deeper. The shared
/// renderer retains the Space's gradients, texture and accessibility choices.
struct BrowserFloatingSidebarCardBackground: View {
    let space: SpaceModel?

    var body: some View {
        ZStack {
            platformBackground
            if let space {
                BrowserSpaceBannerBackground(branding: space.settings.look, surface: .floatingSidebar)
            }
        }
        .accessibilityHidden(true)
    }

    private var platformBackground: Color {
        #if os(macOS)
            OdeColor.windowBackground
        #else
            Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
