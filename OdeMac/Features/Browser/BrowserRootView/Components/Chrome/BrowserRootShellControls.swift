import SwiftUI

struct BrowserRootShellControls: View {
    // MARK: - Variables

    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double
    var sidebarEdge: HorizontalEdge = .leading

    @AppStorage(SidebarHoverRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsOnHover = SidebarHoverRevealPreference.defaultValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - Actions - Presentation

    @ViewBuilder
    var body: some View {
        // With tabs on top, the window's top edge brings the bar out instead.
        switch model.chrome.tabLayout.showsTopBar ? .floating : model.sidebarPresentation.kind {
        case .collapsed:
            BrowserCollapsedSidebarRevealControl(
                capabilities: interactionCapabilities,
                showSidebar: presentFloatingSidebar,
                revealsOnHover: false,
                edge: sidebarEdge,
                isWindowFocused: model.isWindowFocused,
                pointerWidth: revealPointerWidth
            )
            // Shows the strip while its width changes in Settings.
            .background { BrowserSidebarRevealZonePreview() }
            // The Mac shell reveals for a resting pointer through AppKit alone.
            // Live WKWebView content cannot swallow the edge transition before
            // AppKit sees it, and AppKit reports only in the key window. The
            // strip's own hover reads focus a moment late, and reopened the
            // sidebar under a pointer parked at the screen edge just after the
            // window lost focus, where nothing would close it again.
            .overlay {
                if revealMetrics.revealsOnHover, revealsOnHover {
                    BrowserCollapsedSidebarHoverTracker(
                        onHoverChange: collapsedSidebarHoverChanged
                    )
                }
            }
        case .docked:
            resizeHandle(cardInset: 0, docked: true)
                .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
        case .floating:
            // The card's own edge resizes the width the docked sidebar keeps.
            // The card takes the hits around itself, so the handle rides above it.
            // Tabs on top show no sidebar card to resize.
            if !model.chrome.tabLayout.showsTopBar {
                resizeHandle(cardInset: BrowserSidebarPresentation.floatingCardInset, docked: false)
                    .zIndex(BrowserRootMetrics.floatingSidebarResizeControlZIndex)
            }
        }
    }

    /// The handle that resizes the sidebar, at its edge beside the page past
    /// `cardInset`, on whichever side the sidebar is. Beside the docked
    /// sidebar it also collapses it and switches it between icons and the
    /// full sidebar.
    private func resizeHandle(cardInset: CGFloat, docked: Bool) -> some View {
        BrowserSidebarResizeHandle(
            width: docked && model.showsIconSidebar
                ? .constant(BrowserIconSidebarMetrics.width) : model.sidebarWidthBinding,
            onResizeEnded: commitSidebarWidth,
            edge: sidebarEdge,
            onCollapse: docked
                ? { model.hideSidebar(reduceMotion: reduceMotion, keepsCardUnderPointer: false) } : nil,
            showsIcons: docked && model.showsIconSidebar,
            onShowIcons: docked ? { model.setSidebarStyle($0 ? .icons : .full) } : nil
        )
        .offset(
            x: layoutDirection.leadingOffset(
                (cardInset + (docked ? model.shownSidebarWidth : model.sidebarWidth)
                    - BrowserRootMetrics.sidebarResizeHandleOffset)
                    * (sidebarEdge == .leading ? 1 : -1)))
    }

    /// How wide the collapsed sidebar's reveal strip is, as Settings sets it.
    private var revealPointerWidth: CGFloat {
        SidebarRevealWidthPreference.width(BrowserDeviceAppearanceStore.shared.sidebarRevealWidth)
    }

    private var interactionCapabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var revealMetrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(interactionCapabilities)
    }

    // MARK: - Actions - Sidebar

    private func collapsedSidebarHoverChanged(_ isHovering: Bool) {
        guard isHovering, model.isWindowFocused else { return }
        model.revealFloatingSidebarFromPointer(reduceMotion: reduceMotion)
    }

    private func presentFloatingSidebar() {
        model.presentFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        // The column of icons has its own width; the full sidebar keeps its own.
        guard !model.showsIconSidebar || width >= BrowserChromeLayout.sidebarMinimumWidth,
            let committedWidth = model.commitSidebarWidth(width)
        else { return }
        storedSidebarWidth = Double(committedWidth)
    }
}
