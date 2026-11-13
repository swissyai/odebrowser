import SwiftUI

/// A hidden bar of tabs on top: a strip along the window's top edge that
/// brings the bar out over the page for a resting pointer or a click, as the
/// sidebar's edge does, and the bar itself while it is out, as a card that
/// goes away once the pointer leaves it.
struct BrowserTopBarOverlay<Bar: View>: View {
    let model: BrowserRootModel
    let space: SpaceModel?
    @ViewBuilder let bar: () -> Bar

    @AppStorage(SidebarHoverRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsOnHover = SidebarHoverRevealPreference.defaultValue
    private var revealWidth: Double { BrowserDeviceAppearanceStore.shared.sidebarRevealWidth }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserChromeAppearance) private var appearance

    var body: some View {
        VStack(spacing: 0) {
            if model.chrome.isTopBarRevealed {
                card
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            } else {
                revealStrip
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: appearance.cornerScale.surface, style: .continuous)
    }

    private var card: some View {
        bar()
            .background { BrowserFloatingSidebarCardBackground(space: space) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    .primary.opacity(BrowserRootMetrics.floatingSidebarBorderOpacity),
                    lineWidth: BrowserRootMetrics.floatingSidebarBorderWidth
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : BrowserRootMetrics.floatingSidebarShadowOpacity),
                radius: BrowserRootMetrics.floatingSidebarShadowRadius,
                y: BrowserRootMetrics.floatingSidebarShadowOffset
            )
            .padding(BrowserSidebarPresentation.floatingCardInset)
            .overlay {
                BrowserSidebarHoverTracker(isRevealedByPointer: model.isTopBarRevealedByPointer) { isHovering in
                    model.topBarHoverChanged(isHovering, reduceMotion: reduceMotion)
                }
                .accessibilityHidden(true)
            }
    }

    /// The strip that brings the bar out. It is a button, so a click, Full
    /// Keyboard Access and VoiceOver reach it too.
    private var revealStrip: some View {
        Button {
            model.revealTopBar(byPointer: false, reduceMotion: reduceMotion)
        } label: {
            Color.clear.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(height: SidebarRevealWidthPreference.width(revealWidth))
        .frame(maxWidth: .infinity)
        .overlay {
            if revealsOnHover {
                BrowserCollapsedSidebarHoverTracker { isHovering in
                    guard isHovering, model.isWindowFocused else { return }
                    model.revealTopBar(byPointer: true, reduceMotion: reduceMotion)
                }
            }
        }
        .help("Show Tabs")
        .accessibilityLabel("Show Tabs Temporarily")
    }
}
