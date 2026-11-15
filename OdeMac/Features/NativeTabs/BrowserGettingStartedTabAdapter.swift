import SwiftUI

struct BrowserGettingStartedTabAdapter: View {
    let runtime: BrowserNativeTabRuntime
    let bottomChromeHeight: CGFloat
    let openURL: (URL) -> Void
    @Environment(\.browserNativeTabActions) private var actions

    var body: some View {
        BrowserGettingStartedView(
            state: runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() },
            guideContext: { actions.guideContext(runtime.assignment) },
            openSearchSettings: { actions.openSearchSettings(runtime.assignment) },
            browse: { actions.dismiss(runtime.assignment, .gettingStarted) },
            openURL: openURL
        )
    }
}
