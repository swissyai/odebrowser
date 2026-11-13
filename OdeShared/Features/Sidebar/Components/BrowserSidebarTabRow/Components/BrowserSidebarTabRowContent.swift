import SwiftUI

/// What a sidebar tab row draws inside its surface: the tab, the control
/// that hides or shows the tabs nested under it, and the one control that puts
/// it away.
struct BrowserSidebarTabRowContent: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext

    @Environment(\.sidebarRowContentIndent) private var folderIndent

    var body: some View {
        HStack(spacing: configuration.metrics.contentSpacing) {
            leadingContent
            previewBadge
            if let tree = configuration.tree, tree.holdsNestedTabs, !interaction.isRenaming {
                BrowserSidebarTabTreeDisclosure(
                    configuration: configuration, tree: tree, isHovering: interaction.isHovering)
            }
            BrowserSidebarTabTrailingControl(
                configuration: configuration,
                isHovering: interaction.isHovering
            )
            .padding(.trailing, configuration.metrics.contentTrailingInset)
        }
    }

    /// A saved tab's preview badge, which gives way to the row's control
    /// while that shows.
    @ViewBuilder
    private var previewBadge: some View {
        if configuration.tab.placement.isDurable, !interaction.isRenaming,
            let preview = configuration.context.tabPreview(of: configuration.tab.id)
        {
            let isRevealed = configuration.trailingControlMetrics.isRevealed(
                isHovering: interaction.isHovering.wrappedValue, isSelected: configuration.isSelected)
            BrowserTabPreviewBadgeMark(preview: preview, shownTitle: configuration.tab.shownTitle)
                .opacity(isRevealed ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if interaction.isRenaming {
            BrowserSidebarTabRenameField(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset + folderIndent,
                draftTitle: interaction.draftTitle,
                isTitleFocused: interaction.isTitleFocused,
                commitTitle: interaction.commitTitle,
                cancelTitleEditing: interaction.cancelTitleEditing
            )
        } else {
            BrowserSidebarTabActivationButton(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                isSelected: configuration.isSelected,
                isLoaded: configuration.isLoaded,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset + folderIndent,
                restoreSavedLocation: configuration.restoreSavedLocation,
                iconCustomization: BrowserIconCustomizationPresentation(
                    isPresented: interaction.isChoosingIcon,
                    title: "Tab Icon",
                    currentEmoji: configuration.tab.emojiIcon,
                    // Reset applies to explicit icon overrides.
                    showsReset: !configuration.tab.iconMode.followsPage,
                    resetTitle: "Use Website Icon",
                    setEmoji: interaction.setEmojiIcon,
                    reset: interaction.resetIcon
                ),
                select: interaction.activate
            )
            .modifier(
                BrowserTabSelectionAccessibility(
                    tabID: configuration.tab.id, spaceID: configuration.spaceID, browser: configuration.browser,
                    isActive: configuration.isSelected, isLoaded: configuration.isLoaded))
        }
    }
}
