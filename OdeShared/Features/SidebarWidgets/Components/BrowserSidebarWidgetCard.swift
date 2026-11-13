import SwiftUI

struct BrowserSidebarWidgetCard: View {
    // MARK: - Variables

    let instance: BrowserSidebarWidgetInstance
    /// Zero identifies the active card; rear-card content fades with depth.
    let depth: Int
    /// Rear cards use the active card's height.
    let fixedHeight: CGFloat?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    @Environment(\.browserChromeAppearance) private var chromeAppearance
    @State private var isSoftwareUpdateExpanded = false

    private var allowsUpdateCollapsing: Bool {
        guard case .softwareUpdate(let update) = instance.presentation else { return false }
        return update.phase == .available || update.phase == .readyToInstall
    }

    private var isCollapsedUpdate: Bool {
        allowsUpdateCollapsing && !isSoftwareUpdateExpanded
    }

    var body: some View {
        presentation
            .padding(isCollapsedUpdate ? 0 : OdeSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: fixedHeight, alignment: .top)
            .opacity(BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: depth))
            .modifier(BrowserSidebarWidgetCardContentFade(depth: depth))
            .clipShape(shape)
            .modifier(BrowserSidebarWidgetCardChrome(depth: depth, shape: shape))
            .contentShape(shape)
            .accessibilityElement(children: .contain)
    }

    private var shape: RoundedRectangle {
        isCollapsedUpdate
            ? RoundedRectangle(cornerRadius: OdeLayout.sidebarRowHeight / 2, style: .continuous)
            : BrowserSidebarWidgetDeckStyle.cardShape(chromeAppearance.cornerScale)
    }

    @ViewBuilder
    private var presentation: some View {
        switch instance.presentation {
        case .nowPlaying(let session):
            BrowserNowPlayingSidebarWidget(
                instance: instance,
                session: session,
                faviconData: ownerFaviconData(session.owner),
                perform: perform,
                activate: activateMediaSession
            )
        case .softwareUpdate(let update):
            BrowserSoftwareUpdateSidebarWidget(
                instance: instance,
                update: update,
                isExpanded: Binding(
                    get: { !isCollapsedUpdate },
                    set: { isSoftwareUpdateExpanded = $0 }
                ),
                allowsCollapsing: allowsUpdateCollapsing,
                perform: perform
            )
        }
    }

}

/// Fades rear-card controls before the clipping edge.
private struct BrowserSidebarWidgetCardContentFade: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.masksContent(forDepth: depth) {
            content.mask { BrowserSidebarWidgetDeckStyle.contentMask }
        } else {
            content
        }
    }
}

/// Applies the selected glass or custom material treatment. With Reduce
/// Transparency the card is the Space's opaque hover ground.
private struct BrowserSidebarWidgetCardChrome: ViewModifier {
    let depth: Int
    let shape: RoundedRectangle

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(opaqueGround, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(OdeOpacity.border), lineWidth: 0.5) }
        } else if BrowserSidebarWidgetDeckStyle.usesLiquidGlass {
            content.glassEffect(.regular, in: shape)
        } else {
            odeChrome(content)
        }
    }

    private var opaqueGround: Color {
        (spaceColorRoles?.applying(in: colorScheme) ?? SpaceColorRoles(.graphite, colorScheme: colorScheme)).hover.color
    }

    private func odeChrome(_ content: Content) -> some View {
        content
            .background { OdeSurfaceLayer(shape: shape) }
            .overlay {
                shape
                    .stroke(
                        BrowserSidebarWidgetDeckStyle.edgeHighlight(scale: chromeScale),
                        lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    BrowserSidebarWidgetDeckStyle.contactShadowOpacity * chromeScale
                ),
                radius: BrowserSidebarWidgetDeckStyle.contactShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.contactShadowOffset
            )
            .shadow(
                color: .black.opacity(OdeOpacity.controlShadow * chromeScale),
                radius: BrowserSidebarWidgetDeckStyle.ambientShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.ambientShadowOffset
            )
    }

    private var chromeScale: Double {
        depth == 0 ? 1 : BrowserSidebarWidgetDeckStyle.underCardShadowScale
    }
}
