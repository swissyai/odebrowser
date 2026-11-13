import SwiftUI

extension View {
    /// Applies folder indentation and density while allowing accessible text to grow.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserFolderGroupConfiguration
    ) -> some View {
        modifier(BrowserFolderHeaderDensityLayout(configuration: configuration))
    }
}

private struct BrowserFolderHeaderDensityLayout: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }
    @Environment(\.browserChromeAppearance) private var chromeAppearance

    func body(content: Content) -> some View {
        let metrics = configuration.headerMetrics
        let rowHeight = BrowserSidebarDensity(
            dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale, density: chromeAppearance.density
        ).rowHeight(base: OdeLayout.sidebarRowHeight, touch: !metrics.usesFixedRowHeight)
        let height = BrowserFolderLayout.headerHeight(
            rowHeight: rowHeight, tabScale: tabScale, minimum: metrics.iconWidth)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, configuration.headerLeadingInset)
            .padding(.trailing, metrics.contentTrailingInset)
            .frame(
                minHeight: height,
                maxHeight: metrics.usesFixedRowHeight && !dynamicTypeSize.isAccessibilitySize
                    ? height
                    : nil
            )
    }
}
