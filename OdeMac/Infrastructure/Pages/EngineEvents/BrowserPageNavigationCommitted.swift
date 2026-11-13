import Foundation

/// An engine that reports its own navigations committed a new document at
/// `url`, which finished too unless it still loads.
///
/// A navigation within the document, such as a slide's hash or a site's next
/// video, keeps the page's full screen. The engine reports a page that leaves
/// it with its document, except where the page's own script reports it,
/// which goes with the document; there the page reads its full screen back.
struct BrowserPageNavigationCommitted: BrowserPageEngineEvent {
    // MARK: - Variables

    let url: URL?
    let isLoading: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.hasCommittedNavigationAwaitingCompletion = isLoading
        if page.pageEngine.contentScripting != nil { page.confirmContentFullscreen() }
        page.webContentFailureMessage = nil
        page.linkHover?.didCommitNavigation()
        page.mediaSessionCoordinator?.didCommitNavigation()
        page.navigationCommitted(to: url, isLoading: isLoading)
        page.committedNavigationCount += 1
        if !isLoading { page.completedNavigationCount += 1 }
        let authentication = page.httpAuthenticationSession
        Task { await authentication.authenticationSucceeded() }
        page.synchronizePopupPermission(for: url)
        page.sitePermissionSession.synchronize(for: url)
    }
}
