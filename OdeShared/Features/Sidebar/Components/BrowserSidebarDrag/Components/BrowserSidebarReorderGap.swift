import SwiftUI

/// The single vacant slot under a lifted item. Its real height participates in
/// layout, so surrounding rows and folder surfaces settle around the drop.
struct BrowserSidebarReorderGap: View {
    let height: CGFloat
    /// The lift the slot opens for, which lands where the slot is drawn.
    var state: BrowserSidebarReorderState? = nil

    /// The slot takes the shape of a layer where it stands.
    @Environment(\.sidebarLayerDepth) private var depth
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
        shape
            .fill(.primary.opacity(BrowserSidebarReorderVisuals.slotFillOpacity(contrast)))
            .overlay {
                shape.strokeBorder(
                    .primary.opacity(BrowserSidebarReorderVisuals.slotStrokeOpacity(contrast)), lineWidth: 1)
            }
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.vertical, OdeSpacing.extraSmall)
            .frame(height: height)
            .clipped()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                guard height > 0 else { return }
                state?.noteDrawnSlot(frame, inGrid: false)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
