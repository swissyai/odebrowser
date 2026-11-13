import Foundation

struct BrowserUtilityListActions {
    var restoreArchivedTab: (UUID, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var keepArchivedTab: ((UUID, TabPlacement, BrowserSpaceRuntimeAssignment) -> Void)?
    var openHistoryEntry: (HistoryPlace, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var keepHistoryEntry: ((HistoryPlace, TabPlacement, BrowserSpaceRuntimeAssignment) -> Void)?
    var removeHistoryEntry: ((HistoryPlace, BrowserSpaceRuntimeAssignment) -> Void)?
    var removeHistorySite: ((HistoryPlace, BrowserSpaceRuntimeAssignment) -> Void)?
    /// Reads the history the core keeps beside the session; without one, a
    /// history list shows the session's newest entries.
    var readHistory: BrowserHistoryReader?
    var downloadDestinations: [BrowserUtilityDownloadDestination] = []
    /// The shell can move a finished file to the Trash from its row.
    var offersMoveToTrash = false
    var performDownloadAction: (BrowserUtilityDownloadAction, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    /// Clears the finished, canceled and failed downloads of the Space at the
    /// assignment, where the shell offers it.
    var clearDownloads: ((BrowserSpaceRuntimeAssignment) -> Void)?
}
