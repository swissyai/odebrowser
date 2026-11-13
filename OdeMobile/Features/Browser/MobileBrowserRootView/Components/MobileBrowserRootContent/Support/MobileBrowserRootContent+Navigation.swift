import SwiftUI
import UIKit

extension MobileBrowserRootContent {
    func selectTab(_ id: UUID) {
        dismissAddressFocus()
        let dismissesFloatingPhoneSidebar =
            presentation.dismissesSidebarOnTabSelection(
                sidebarPresentation: navigation.regularSidebarPresentation
            )
        model.selectTab(id)
        if dismissesFloatingPhoneSidebar {
            hideRegularSidebar()
        }
    }

    func submitAddress() {
        guard model.submitAddress() else { return }
        isAddressEditing = false
    }

    func openURL(_ url: URL) {
        model.openURL(url)
    }

    func beginNewTab() {
        guard !suspendsCompactPagePresentation, model.beginFreshQuery() else { return }
        commandPaletteMode = nil
        presentation.beginNewTab(in: self)
    }

    func consumeFreshQueryRequest() {
        guard canConsumeFreshQuery else { return }
        guard
            model.consumeFreshQueryRequest(
                isReady: availableRootSize.width > 0,
                isObscured: suspendsCompactPagePresentation
            )
        else { return }
        beginNewTab()
    }

    func settingsSheetDidDismiss() {
        model.settings.sheetDidDismiss()
        if model.passwordsArePresentedFromSettings { model.passwordsSheetDidDismiss() }
        consumeFreshQueryRequest()
    }

    func listSheetDidDismiss() {
        model.listSheetDidDismiss()
        consumeFreshQueryRequest()
    }

    func passwordsSheetDidDismiss() {
        model.passwordsSheetDidDismiss()
        consumeFreshQueryRequest()
    }

    func openLocation() {
        presentation.openLocation(in: self)
    }

    func focusStartPageCommandPalette() {
        model.focusStartPageAddress()
        isAddressEditing = false
        paletteFocusGrant.grant()
        addressFocusRequest &+= 1
    }

    /// Opens the launch's new tab. Only a narrow window with the height for a
    /// keyboard puts it up for the tab, as a phone held upright starts on its
    /// search field; a short or wide window leaves the field until a tap.
    func beginLaunchNewTab() {
        if presentation.focusesAddressAtLaunch(verticalSizeClass: verticalSizeClass) {
            beginNewTab()
        } else if presentation.presentsPageOverTabViewer {
            model.beginCompactNewTab()
        }
    }

    /// Ends whatever address editing the window had open, for a request such
    /// as a link from another app arriving while the person was typing.
    func endAddressEditing() {
        dismissAddressFocus()
        commandPaletteMode = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func showTabViewer() {
        dismissAddressFocus()
        model.showTabViewer()
    }

    func finishCompactTransition(_ predictedEndTranslation: CGSize) {
        guard presentation.presentsPageOverTabViewer else { return }
        guard compactTransition.commits(predictedEndTranslation: predictedEndTranslation) else { return }
        isAddressEditing = false
        compactTransition.finish(in: self)
    }

    /// Brings the sidebar up from the compact chrome's upward swipe, in the
    /// placement this window already keeps it in.
    ///
    /// `MobileCompactSidebarRevealDestination` carries the reasoning. The short of it
    /// is that the full-screen viewer is the docked sidebar, so a docked window
    /// goes on landing there, while an undocked one — which only has this
    /// toolbar to swipe because a split is on show — floats the sidebar over the
    /// split instead of dropping the split to reach it.
    func revealSidebarFromCompactChrome() {
        MobileCompactSidebarRevealDestination.destination(
            sidebarPresentation: navigation.regularSidebarPresentation
        )
        .reveal(in: self)
    }

    /// Shows the tab the address bar's swipe landed on, which the core chose
    /// from the shown Space. Keyboard Space switching (⌥⌘←/→) goes through
    /// `MobileBrowserCommandController`, not through here, and the swipe never
    /// switches Spaces.
    func showSwipedTab(_ tabID: UUID) {
        model.showSwipedTab(tabID)
    }

    func toggleSidebarFromCommand() {
        if presentation.presentsPageOverTabViewer, navigation.compactShowsPage {
            dismissAddressFocus()
        }
        model.toggleSidebar(
            presentation: presentation,
            reduceMotion: reduceMotion
        )
    }

    func hideRegularSidebar() {
        model.hideRegularSidebar(reduceMotion: reduceMotion)
    }

    func showRegularSidebar() {
        model.showRegularSidebar(reduceMotion: reduceMotion)
    }

    func toggleRegularSidebar() {
        model.toggleSidebar(
            presentation: .regular,
            reduceMotion: reduceMotion
        )
    }

    func commitRegularSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedRegularSidebarWidth = Double(committedWidth)
    }

    func toggleCompactSidebar() {
        dismissAddressFocus()
        model.toggleSidebar(
            presentation: .compact,
            reduceMotion: reduceMotion
        )
    }

    func dismissAddressFocus() {
        model.startPageQueryFocusBinding.wrappedValue = false
        isAddressEditing = false
        BrowserAddressFocusDismissal.dismiss()
    }
}
