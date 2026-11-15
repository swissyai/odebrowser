import SwiftUI

/// Observes outcomes in this window, never keys or text. The real Command Bar
/// keeps its input focus and remains entirely responsible for its shortcuts.
struct BrowserGettingStartedTourPresentation: ViewModifier {
    // MARK: - Variables

    let model: BrowserMacWindowModel

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content
            .environment(model.chrome.gettingStartedTour)
            .onChange(of: model.browser.gettingStartedTourRequest, initial: true) { _, request in
                guard let request else { return }
                model.chrome.gettingStartedTour?.start(request, automatically: true)
                model.browser.gettingStartedTourRequest = nil
            }
            .onChange(of: model.browser.sessionRevision) {
                guard let tour = model.chrome.gettingStartedTour, tour.isRunning, !tour.isShowingGuide else { return }
                tour.dismiss()
            }
    }
}
