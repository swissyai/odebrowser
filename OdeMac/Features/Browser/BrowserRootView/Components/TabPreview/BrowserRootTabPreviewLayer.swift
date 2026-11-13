import SwiftUI

/// The window's preview card: beside the sidebar, level with the pinned or
/// saved tab the pointer rests on, kept inside the window. It shows only for
/// a tab of the Space the window shows, unlocked, and goes when the window
/// shows another tab or Space.
struct BrowserRootTabPreviewLayer: View {
    // MARK: - Static Variables

    /// The space between the sidebar and the card, and the least between the
    /// card and the window's edges.
    private static let gap: CGFloat = 8
    /// How far above its tab's top the card's top sits.
    private static let rise: CGFloat = 6

    // MARK: - Variables

    let model: BrowserRootModel
    let sidebarOnRight: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardSize = CGSize(width: BrowserTabPreviewCard.width, height: 0)

    private var hover: BrowserTabPreviewHover { model.chrome.tabPreviewHover }

    var body: some View {
        GeometryReader { proxy in
            let root = proxy.frame(in: .global)
            ZStack(alignment: .topLeading) {
                if let target = hover.shown, let card = card(for: target) {
                    let origin = origin(for: target.frame, in: root)
                    card
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: { frame in
                            guard hover.shown?.assignment == target.assignment else { return }
                            cardSize = frame.size
                            hover.card(of: target.assignment, isAt: frame)
                        }
                        .onHover { hover.card(isHovered: $0) }
                        .padding(.leading, origin.x)
                        .padding(.top, origin.y)
                        .transition(transition)
                        .id(target.assignment)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(animation, value: hover.shown?.assignment)
        }
        .onChange(of: model.browser.shownTab?.id) { hover.dismiss() }
        .onChange(of: model.browser.shownSpace?.id) { hover.dismiss() }
        .onChange(of: model.chrome.isCommandPalettePresented) { hover.dismiss() }
        .onAppear {
            hover.willShow = { [weak pages = model.pages] assignment in
                pages?.runtimeStore.tabPreviews.hover(assignment.tabID)
            }
        }
    }

    // MARK: - Actions - Card

    private func card(for target: BrowserTabPreviewHover.Target) -> BrowserTabPreviewCard? {
        let assignment = target.assignment
        guard let space = model.browser.shownSpace, space.id == assignment.spaceID,
            space.profileID == assignment.profileID, !model.spaceAccess.isLocked(space),
            let tab = space.tabs.model(assignment.tabID), tab.placement.isDurable,
            let preview = model.pages.tabPreview(matching: assignment),
            let site = model.pages.tabPreviewSite(matching: assignment)
        else { return nil }
        return BrowserTabPreviewCard(
            preview: preview, site: site, tab: tab, favicons: model.browser.core.state.favicons,
            profileID: space.profileID
        ) { [weak hover, weak pages = model.pages] item in
            hover?.dismiss()
            pages?.openTabPreviewItem(item, in: assignment)
        }
    }

    /// Where the card's top leading corner goes: past the sidebar on the
    /// page's side, its top level with the tab's, inside the window.
    private func origin(for tab: CGRect, in root: CGRect) -> CGPoint {
        let sidebar = model.shownSidebarWidth
        let x =
            sidebarOnRight
            ? min(tab.minX - root.minX, root.width - sidebar) - Self.gap - cardSize.width
            : max(tab.maxX - root.minX, sidebar) + Self.gap
        let top = tab.minY - root.minY - Self.rise
        let y = min(max(top, Self.gap), max(root.height - cardSize.height - Self.gap, Self.gap))
        return CGPoint(x: max(x, Self.gap), y: y)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.97, anchor: sidebarOnRight ? .trailing : .leading))
    }

    private var animation: Animation {
        reduceMotion ? OdeMotion.reducedMotionFade : OdeMotion.feedbackPresentation
    }
}
