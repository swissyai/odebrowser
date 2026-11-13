import SwiftUI

/// Pauses the shown page once its site used its daily limit, over the page
/// alone, and counts the time a limited site is on screen while the window
/// has the keyboard. Sites without a limit are never counted.
struct BrowserFocusPauseLayer: View {
    let model: BrowserRootModel
    let pageRect: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var preferences = BrowserAppPreferenceStore.shared
    private let keeper = BrowserFocusTimeKeeper.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            if let page = model.pages.activePage, let site = BrowserSite.of(page.live.displayURL),
                let limit = preferences.focus.limit(for: site), keeper.isPaused(site, limit: limit)
            {
                BrowserFocusPauseView(
                    site: site, limit: limit,
                    extend: { keeper.grantExtraTime(on: site, limit: limit) },
                    closeTab: {
                        if let tabID = model.browser.shownTab?.id { _ = model.browser.closeTab(tabID) }
                    }
                )
                .frame(width: pageRect.width, height: pageRect.height)
                .position(x: pageRect.midX, y: pageRect.midY)
                .transition(.opacity)
                .onAppear {
                    keeper.pausedOnScreen.insert(site)
                    page.pauseMedia()
                }
                .onDisappear { keeper.pausedOnScreen.remove(site) }
            }
        }
        .animation(reduceMotion ? nil : OdeMotion.collection, value: countedSite)
        .onChange(of: countedSite, initial: true) { _, site in
            keeper.show(site, in: model.pages.windowID)
        }
        .onDisappear { keeper.show(nil, in: model.pages.windowID) }
    }

    /// The limited site the window shows while it has the keyboard, which
    /// the keeper counts.
    private var countedSite: String? {
        guard model.isWindowFocused, let site = BrowserSite.of(model.pages.activePage?.live.displayURL),
            preferences.focus.limit(for: site) != nil
        else { return nil }
        return site
    }
}
