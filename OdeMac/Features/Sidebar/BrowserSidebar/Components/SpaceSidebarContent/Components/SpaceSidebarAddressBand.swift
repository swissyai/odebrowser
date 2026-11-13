import SwiftUI

/// Fixed address controls. The pager owns the changing extension-strip seam
/// so semantic selection cannot resize the viewport during a Space transition.
struct SpaceSidebarAddressBand: View {
    // MARK: - Variables

    let space: SpaceModel
    /// Whether the site controls act for `space`; they offer nothing while it
    /// is being deleted.
    let offersSiteControls: Bool
    /// The tab this window shows in `space`.
    let selectedTabID: UUID?
    let pages: BrowserPagePool
    let capabilities: BrowserInteractionCapabilities
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let commandPaletteHandoff: BrowserCommandPaletteHandoff
    let siteControlPresentationChanged: (Bool) -> Void
    let siteControlContextMenuPresentationChanged: (Bool) -> Void
    var showsSummaryRoute = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserSidebarAddressField(configuration: addressConfiguration) {
            if let siteControl {
                BrowserAddressSecurityButton(
                    page: siteControl.page,
                    isSecure: isSecure
                )
            }
        } trailingAccessory: {
            if let siteControl {
                if let copyURLPage {
                    BrowserAddressCopyURLButton(page: copyURLPage)
                }
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
        .contentTransition(.opacity)
        .animation(
            SpacePagerSettlement.standardAnimation.unlessReducingMotion(reduceMotion),
            value: isAddressEditing.wrappedValue ? nil : address.wrappedValue
        )
        .padding(.horizontal, BrowserSidebarMetrics.layerInset)

    }

    private var addressConfiguration: BrowserSidebarAddressFieldConfiguration {
        BrowserSidebarAddressFieldConfiguration(
            text: address,
            isEditing: isAddressEditing,
            showsSummaryRoute: showsSummaryRoute,
            focusRequest: addressFocusRequest,
            isSecure: isSecure,
            progress: displayedPage?.estimatedProgress ?? 0,
            isLoading: displayedPage?.live.isLoading == true,
            hasResidentPage: displayedPage != nil,
            hasActiveSite: siteControl != nil,
            capabilities: capabilities,
            activate: activateAddress,
            submit: submitAddress,
            morphNamespace: commandSurfaceNamespace,
            spaceID: space.id,
            commandPaletteHandoff: commandPaletteHandoff,
            branding: space.settings.look,
            copyAddress: siteControl.map { configuration in
                { BrowserAddressCopyURLButton.copy(configuration.page) }
            }
        )
    }

    private var selectedTab: TabStateModel? {
        selectedTabID.flatMap { space.shownTab($0) }
    }

    private var displayedPage: BrowserPage? {
        guard let selectedTabID else { return nil }
        let assignment = BrowserTabRuntimeAssignment(
            tabID: selectedTabID, spaceID: space.id, profileID: space.profileID
        )
        return pages.activePage(matching: assignment)
    }

    private var isSecure: Bool {
        if let page = displayedPage { return page.live.security.isSecure }
        return selectedTab?.url.flatMap(URL.init(string:))?.scheme?.lowercased() == "https"
    }

    /// The page the Copy URL button copies, while the person turned the
    /// button on and the page has an address to copy.
    private var copyURLPage: BrowserPage? {
        guard BrowserDeviceAppearanceStore.shared.address.showsCopyURLButton,
            let page = displayedPage, page.live.documentURL != nil
        else { return nil }
        return page
    }

    private var siteControl: BrowserSiteControlConfiguration? {
        guard pages.browser.workspaceModel?.kind.isPractice != true, offersSiteControls, let page = displayedPage,
            page.live.displayURL != nil
        else {
            return nil
        }
        return BrowserSiteControlConfiguration(
            page: page,
            space: space,
            selectedTabID: selectedTabID,
            permissionCenter: pages.permissionCenter,
            tabPreviews: pages.runtimeStore.tabPreviews,
            presentationChanged: siteControlPresentationChanged,
            contextMenuPresentationChanged:
                siteControlContextMenuPresentationChanged
        )
    }
}
