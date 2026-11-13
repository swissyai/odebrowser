import SwiftUI

/// The control on a tab that tabs nest under: how many it hides while it hides
/// them, and a chevron that hides or shows them. While they are hidden it
/// always shows; while they show, it appears with the row's other control.
struct BrowserSidebarTabTreeDisclosure: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let tree: BrowserSidebarTabTree
    @Binding var isHovering: Bool

    var body: some View {
        let collapsed = tree.collapsesNestedTabs
        let metrics = configuration.trailingControlMetrics
        let isVisible =
            collapsed || metrics.isRevealed(isHovering: isHovering, isSelected: configuration.isSelected)
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            configuration.browser.collapseNestedTabs(
                !collapsed, under: configuration.tab.id, matching: configuration.assignment)
        } label: {
            HStack(spacing: OdeSpacing.extraExtraSmall) {
                if collapsed {
                    Text(tree.nestedTabs, format: .number)
                        .monospacedDigit()
                }
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: metrics.glyphSize, weight: metrics.glyphWeight))
            }
            .font(.caption)
            .padding(.horizontal, collapsed ? OdeSpacing.extraSmall : 0)
            .frame(minWidth: metrics.controlSize.width, minHeight: metrics.controlSize.height)
            .contentShape(.rect)
        }
        .modifier(DisclosureStyle(metrics: metrics))
        .foregroundStyle(.secondary)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .disabled(!configuration.isAvailableForDisplay)
        .help(collapsed ? Text("Show Nested Tabs") : Text("Hide Nested Tabs"))
        .accessibilityLabel(collapsed ? Text("Show \(tree.nestedTabs) nested tabs") : Text("Hide nested tabs"))
    }
}

/// The chrome's hover-and-press treatment where a pointer can earn it, and a
/// plain button where nothing can, as the row's other control has.
private struct DisclosureStyle: ViewModifier {
    let metrics: BrowserTabTrailingControlMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if metrics.usesChromeControlStyle {
            content.buttonStyle(OdeChromeButtonStyle(controlSize: nil))
        } else {
            content.buttonStyle(.plain)
        }
    }
}
