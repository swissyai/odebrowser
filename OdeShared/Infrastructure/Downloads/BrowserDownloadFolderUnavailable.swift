import Foundation

/// The Space's download folder is unavailable, so a download's file has no
/// place to go.
struct BrowserDownloadFolderUnavailable: BrowserPlatformDownloadResolution {
    // MARK: - Actions - Downloads

    @MainActor func answer(_ asked: DownloadDestinationAsked, for prompts: BrowserDownloadPrompts) {
        _ = try? prompts.core?.send(
            FailDownload(downloadID: asked.downloadID, reason: .folderUnavailable, message: nil))
        prompts.answer(AnswerDownloadDestination(promptID: asked.promptID, path: nil))
    }

    func abandon() {}

    @MainActor func save(_ data: Data, as itemID: UUID, from originatingURL: URL, in center: BrowserDownloadCenter) {
        #if os(macOS)
            center.send(
                FailDownload(
                    downloadID: itemID, reason: .folderUnavailable,
                    message:
                        "The download folder is unavailable. Open Ode Settings > Privacy & Permissions > Files & Folders to check folder access, or choose another folder on the Space's Browsing page."
                ))
        #else
            center.send(FailDownload(downloadID: itemID, reason: .folderUnavailable, message: nil))
        #endif
    }
}
