import Foundation

struct BrowserSiteControlConfiguration {
    let page: BrowserPage
    /// The page's Space in the read model, which the engine's extension
    /// controls act for.
    let space: SpaceModel
    let selectedTabID: UUID?
    let permissionCenter: BrowserSitePermissionCenter
    /// The previews of the workspace's pinned and saved tabs.
    let tabPreviews: BrowserTabPreviewCenter
    let presentationChanged: (Bool) -> Void
    let contextMenuPresentationChanged: (Bool) -> Void
}
