import SwiftUI

/// Notes the everyday moves a browser window shows the person making: the
/// Command Bar opening, a Split View on screen, a Peek, and a change of
/// Space. What a window shows as it opens counts for nothing.
struct BrowserGettingStartedMoveObserver: ViewModifier {
    let model: BrowserMacWindowModel
    let moves: BrowserGettingStartedMoves

    func body(content: Content) -> some View {
        content
            .onChange(of: model.chrome.isCommandPalettePresented) { _, isPresented in
                if isPresented { moves.record(.commandBar) }
            }
            .onChange(of: model.pages.presentedTabIDs.count) { _, count in
                if count > 1 { moves.record(.splitView) }
            }
            .onChange(of: model.transientBrowsing.peekRequest != nil) { _, isPeeking in
                if isPeeking { moves.record(.peek) }
            }
            .onChange(of: model.browser.selectedSpaceID) {
                moves.record(.switchSpace)
            }
    }
}
