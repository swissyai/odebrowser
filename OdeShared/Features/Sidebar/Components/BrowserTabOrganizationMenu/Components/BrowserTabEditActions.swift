import SwiftUI

struct BrowserTabEditActions: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let restoreSavedLocation: (() -> Void)?
    let performIfCurrent: (() -> Void) -> Void
    let replaceSavedLocation: () -> Void
    let clearIcon: () -> Void
    let changeIcon: () -> Void
    let tidyTitle: () -> Void
    let restoreOriginalTitle: () -> Void

    @AppStorage(BrowserIntelligencePreference.enabledKey)
    private var isIntelligenceEnabled = BrowserIntelligencePreference.defaultEnabled

    var body: some View {
        if tab.supportsSavedLocationEditing {
            Menu("Edit Tab", systemImage: "pencil") {
                Group {
                    Button(
                        "Replace with Current URL",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        performIfCurrent(replaceSavedLocation)
                    }
                    .disabled(!tab.isAwayFromSavedAddress)

                    Button(
                        "Return to Saved URL",
                        systemImage: "arrow.uturn.backward"
                    ) {
                        performIfCurrent { restoreSavedLocation?() }
                    }
                    .disabled(
                        !tab.isAwayFromSavedAddress
                            || restoreSavedLocation == nil
                    )

                    Divider()
                    titleActions
                    iconActions
                }
                .odeMenuActionLabelStyle()
            }
        } else {
            titleActions
            iconActions
        }
    }

    /// Present only while intelligence is on. Only a pinned or saved web page
    /// is tidied, so current tabs, downloads and files keep their titles.
    @ViewBuilder
    private var titleActions: some View {
        if isIntelligenceEnabled {
            let tidiesTitle = tab.isWebPage && tab.placement.isDurable
            let hasCustomTitle = BrowserShownTitle.resolve(tab.customTitle) != nil
            if tidiesTitle {
                Button("Tidy Title", systemImage: "wand.and.sparkles") {
                    performIfCurrent(tidyTitle)
                }
            }
            if hasCustomTitle {
                Button("Restore Original Title", systemImage: "arrow.uturn.backward") {
                    performIfCurrent(restoreOriginalTitle)
                }
            }
            if tidiesTitle || hasCustomTitle {
                Divider()
            }
        }
    }

    private var iconActions: some View {
        BrowserTabIconActions(
            tab: tab,
            favicons: favicons,
            isLoaded: isLoaded,
            pullNewIcon: pullNewIcon,
            performIfCurrent: performIfCurrent,
            clearIcon: clearIcon,
            changeIcon: changeIcon
        )
    }
}
