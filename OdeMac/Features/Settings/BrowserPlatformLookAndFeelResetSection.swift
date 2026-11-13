import SwiftUI

/// The desktop's Reset All: the shared choices, plus Space page motion and the
/// Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarHoverRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarOnHover = SidebarHoverRevealPreference.defaultValue
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            BrowserDeviceAppearanceStore.shared.sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
            revealsSidebarOnHover = SidebarHoverRevealPreference.defaultValue
            revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue
            _ = BrowserMacDockTile.shared.select("")
        }
    }
}
