import SwiftUI

/// A Space as the Ode window shows it: its field across the whole window,
/// its sidebar on the left with the Space's name among its tabs, and the page
/// card inset beside it, measured as the real window is. The name is edited
/// in place where the preview is given it.
struct BrowserOnboardingWindowPreview<Page: View>: View {
    // MARK: - Variables

    @Environment(\.colorScheme) private var colorScheme
    let branding: SpaceBranding
    let symbol: String
    let name: String
    var editableName: Binding<String>? = nil
    /// Actual content when customizing or completing setup. Only a pre-import
    /// demonstration or a newly drafted Space falls back to sample tabs.
    var previewSpace: SpaceModel? = nil
    var favicons = FaviconAssets()
    var tabLayout = BrowserTabLayout.sidebar
    var sidebarOnRight = false
    var addressPlacement = BrowserAddressPlacement.defaultValue
    @ViewBuilder let page: Page

    /// Content is read-only. Draft appearance is rendered separately, never
    /// written onto the workspace's Space from a view.
    private var space: SpaceModel {
        if let previewSpace { return previewSpace }
        return SpaceModel.detached(
            SessionState.Seed.showcase.spaces[0].wearing(
                branding, symbol: symbol, name: name.isEmpty ? String(localized: "Your Space") : name))
    }

    private var shownName: String { name.isEmpty ? String(localized: "Your Space") : name }

    var body: some View {
        let space = space
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)
            // A small window narrows its sidebar rather than cutting it off.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if tabLayout.showsTopBar {
                        topBar(space)
                        pageCard
                    } else {
                        HStack(spacing: 0) {
                            if !sidebarOnRight { previewSidebar(space, width: proxy.size.width) }
                            VStack(spacing: 0) {
                                if addressPlacement.showsTopBar {
                                    addressField
                                        .padding(.horizontal, OdeSpacing.small)
                                        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
                                }
                                pageCard
                            }
                            if sidebarOnRight { previewSidebar(space, width: proxy.size.width) }
                        }
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.14), lineWidth: OdeLayout.hairline)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .spaceColorRoles(for: branding)
        .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: space, isUnlocked: true))
        .accessibilityElement(children: editableName == nil ? .ignore : .contain)
        .accessibilityLabel("Preview of \(shownName) in an Ode window")
    }

    // MARK: - Actions - Preview

    private func identity(of space: SpaceModel) -> BrowserSpaceIdentity {
        space.identity.wearing(branding, symbol: symbol, name: shownName)
    }

    private func previewSidebar(_ space: SpaceModel, width: CGFloat) -> some View {
        sidebar(space)
            .frame(width: min(BrowserChromeLayout.sidebarIdealWidth, max(150, width * 0.45)))
    }

    /// These are the same tab controls the real top bar renders, over the
    /// same Space as the sidebar preview. Only their preview actions are inert.
    private func topBar(_ space: SpaceModel) -> some View {
        HStack(spacing: OdeSpacing.small) {
            BrowserSpaceIcon(identity: identity(of: space), size: 22)
            ScrollView(.horizontal) {
                HStack(spacing: OdeSpacing.extraExtraSmall) {
                    ForEach(space.shownPins + space.currentTabs) { tab in
                        BrowserTopTab(
                            tab: tab, space: space, favicons: favicons,
                            isSelected: tab.id == space.currentTabs.first?.id,
                            showsTitle: tab.placement != .pinned, width: 140,
                            select: {}, close: {}, togglePin: {}, duplicate: {})
                    }
                }
            }
            .scrollIndicators(.never)
            Image(systemName: "plus")
            Image(systemName: "sidebar.leading")
        }
        .padding(.horizontal, 14)
        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
        .allowsHitTesting(false)
    }

    /// The page beside the sidebar, inset as the window insets it.
    private var pageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrowserChromeLayout.pageCornerRadius, style: .continuous)
                .fill(OdeBrandTheme.surface)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            page
        }
        .padding(.vertical, BrowserChromeLayout.pageFrameInset)
        .padding(sidebarOnRight && !tabLayout.showsTopBar ? .leading : .trailing, BrowserChromeLayout.pageFrameInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebar(_ space: SpaceModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titlebar
            if !addressPlacement.showsTopBar {
                addressField
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
            PinnedTabGrid(
                tabs: space.shownPins, favicons: favicons, assignment: BrowserSpaceRuntimeAssignment(space: space),
                select: { _ in }
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .allowsHitTesting(false)
            spaceRow(space)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            BrowserOdeImportTabList(
                space: space, favicons: favicons, matchedTabIDs: [], highlightedTabID: space.currentTabs.first?.id
            )
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .allowsHitTesting(false)
            bottomBar(space)
        }
    }

    /// The window's controls and the sidebar's navigation, as the title bar
    /// holds them.
    private var titlebar: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(.primary.opacity(0.22)).frame(width: 12, height: 12)
            }
            Spacer()
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right").opacity(0.45)
            Image(systemName: "arrow.clockwise")
                .padding(.leading, 4)
        }
        .font(.system(size: BrowserChromeLayout.sidebarNavigationSymbolPointSize, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
        .accessibilityHidden(true)
    }

    private var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Search or enter website").lineLimit(1)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: BrowserChromeLayout.addressHeight)
        .browserAddressFieldSurface(progress: 0, isLoading: false, isEditing: false, branding: branding)
        .accessibilityHidden(true)
    }

    private func spaceRow(_ space: SpaceModel) -> some View {
        HStack(spacing: 10) {
            BrowserSpaceIcon(identity: identity(of: space), size: 22)
                .frame(width: 22, height: 22)
            if let editableName {
                BrowserInlineSpaceName(
                    name: editableName, size: 15, titleFont: OdeTypography.sans(15, weight: .semibold))
            } else {
                Text(shownName).font(OdeTypography.sans(15, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 32)
    }

    private func bottomBar(_ space: SpaceModel) -> some View {
        HStack {
            Image(systemName: "arrow.down.circle")
            Spacer()
            BrowserSpaceIcon(identity: identity(of: space), size: 22)
                .frame(width: 22, height: 22)
                .padding(5)
                .background(.primary.opacity(0.12), in: .rect(cornerRadius: OdeCornerScale.control, style: .continuous))
            Spacer()
            Image(systemName: "archivebox")
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

enum BrowserOnboardingWindowPreviewMetrics {
    /// The preview window's corner: its page's corner and the gutter around
    /// the page, so the two stay concentric.
    static let cornerRadius = BrowserChromeLayout.pageCornerRadius + OdeCornerScale.gutter
}
