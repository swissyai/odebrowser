import SwiftUI

/// The title of the icon the pointer rests on in the sidebar as icons, beside
/// the column on the page's side, level with the icon. Each icon also names
/// itself to VoiceOver, so the title itself is hidden from it.
struct BrowserIconSidebarTitleLayer: View {
    // MARK: - Static Variables

    /// The space between the icon's column and the title.
    private static let gap: CGFloat = 6

    // MARK: - Variables

    let hover: BrowserIconSidebarHover
    let sidebarOnRight: Bool

    @Environment(\.browserChromeAppearance) private var appearance

    var body: some View {
        GeometryReader { proxy in
            let root = proxy.frame(in: .global)
            ZStack(alignment: sidebarOnRight ? .topTrailing : .topLeading) {
                if let shown = hover.shown {
                    Text(verbatim: shown.title)
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, OdeSpacing.small)
                        .padding(.vertical, OdeSpacing.extraSmall)
                        .background {
                            OdeSurfaceLayer(shape: .rect(cornerRadius: appearance.cornerScale.inset))
                        }
                        .frame(height: shown.frame.height)
                        .padding(.top, shown.frame.minY - root.minY)
                        .padding(sidebarOnRight ? .trailing : .leading, inset(of: shown.frame, in: root))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sidebarOnRight ? .topTrailing : .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How far from the window's edge the title starts: past the icon's
    /// column, on the page's side.
    private func inset(of icon: CGRect, in root: CGRect) -> CGFloat {
        let column = BrowserIconSidebarMetrics.width
        return sidebarOnRight
            ? max(0, root.maxX - icon.minX) + (column - icon.width) / 2 + Self.gap
            : max(0, icon.maxX - root.minX) + (column - icon.width) / 2 + Self.gap
    }
}
