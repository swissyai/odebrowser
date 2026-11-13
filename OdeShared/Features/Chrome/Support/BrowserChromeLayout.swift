import SwiftUI

enum BrowserChromeLayout {
    static let sidebarTitlebarHeight: CGFloat = 48
    static let sidebarNavigationControlHitTarget: CGFloat = 30
    static let sidebarNavigationSymbolPointSize: CGFloat = 15
    static let sidebarNavigationTrailingInset = OdeSpacing.medium
    static let addressEditingRingWidth: CGFloat = 0.5
    static let addressHeight: CGFloat = 36
    static let addressCornerRadius = OdeRadius.compact
    static let sidebarMinimumWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 289
    static let sidebarMaximumWidth: CGFloat = 380
    /// A drag that ends with the sidebar's edge this close to the window's
    /// puts the sidebar away.
    static let sidebarCollapseWidth: CGFloat = 60
    /// A drag that ends with the sidebar narrower than this, and wider than
    /// the collapse width, shows the sidebar as icons, where the shell can.
    static let sidebarIconsWidth: CGFloat = 150
    static let pageFrameInset = OdeSpacing.small
    /// A page's corner where there is no window corner to follow: full screen,
    /// iPhone and iPad.
    static let pageCornerRadius = OdeCornerScale(window: nil).surface

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinimumWidth), sidebarMaximumWidth)
    }
}
