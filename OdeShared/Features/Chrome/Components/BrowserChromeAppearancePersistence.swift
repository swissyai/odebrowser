import SwiftUI

/// Supplies live appearance preferences and the window's own corner at the
/// scene boundary. Page frames read the device's border and sidebar side from
/// ``BrowserDeviceAppearanceStore``; the layout choices, the sidebar side and
/// the border once it settles reach the views that arrange tabs through the
/// environment.
struct BrowserChromeAppearancePersistence: ViewModifier {
    @AppStorage(BrowserChromeAppearancePreference.borderWidthKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderWidth = BrowserChromeAppearance.defaultBorderWidth
    @AppStorage(BrowserChromeAppearancePreference.tabLayoutKey, store: BrowserChromeAppearancePreference.defaults)
    private var tabLayout = BrowserTabLayout.defaultValue.name
    @AppStorage(BrowserChromeAppearancePreference.densityKey, store: BrowserChromeAppearancePreference.defaults)
    private var density = BrowserLayoutDensity.defaultValue.name
    @AppStorage(BrowserChromeAppearancePreference.sidebarStyleKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarStyle = BrowserSidebarStyle.defaultValue.name
    /// The corner radius of the window this scene fills, which the page frame
    /// follows on Mac.
    @State private var windowCornerRadius: CGFloat?
    @State private var isWindowFullScreen = false

    /// The sidebar as icons is the Mac's alone; other shells keep it in full.
    private var sidebarStyleChoice: BrowserSidebarStyle {
        #if os(macOS)
            BrowserSidebarStyle.named(sidebarStyle)
        #else
            .full
        #endif
    }

    /// Tabs on top are the Mac's alone; other shells keep their sidebar.
    private var tabLayoutChoice: BrowserTabLayout {
        #if os(macOS)
            BrowserTabLayout.named(tabLayout)
        #else
            .sidebar
        #endif
    }

    func body(content: Content) -> some View {
        content
            .environment(
                \.browserChromeAppearance,
                BrowserChromeAppearance(
                    sidebarOnRight: BrowserDeviceAppearanceStore.shared.sidebarOnRight,
                    borderWidth: borderWidth,
                    windowCornerRadius: isWindowFullScreen ? nil : windowCornerRadius,
                    tabLayout: tabLayoutChoice,
                    density: BrowserLayoutDensity.named(density),
                    sidebarStyle: sidebarStyleChoice
                )
            )
            .environment(\.browserWindowCornerRadius, isWindowFullScreen ? nil : windowCornerRadius)
            #if os(macOS)
                // The window's corners change shape with its chrome, so the
                // radius is read live rather than assumed.
                .onGeometryChange(for: CGFloat?.self) { proxy in
                    BrowserChromeAppearance.windowCornerRadius(from: proxy.containerCornerInsets)
                } action: { radius in
                    windowCornerRadius = radius
                }
                // A full-screen window keeps reporting the corners it has as a
                // window, so whether it is full screen comes from AppKit.
                .background {
                    BrowserWindowFullScreenBridge(isFullScreen: $isWindowFullScreen).accessibilityHidden(true)
                }
            #endif
    }
}
