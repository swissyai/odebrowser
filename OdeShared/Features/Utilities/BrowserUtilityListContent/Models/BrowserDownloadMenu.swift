import Foundation

/// What a download row's menu offers, in groups the menu divides: a running
/// download pauses, resumes or cancels; a finished file goes to each of the
/// shell's destinations, then leaves the list or goes to the Trash; anything
/// else leaves the list, after the person allows a blocked one or resumes a
/// failed one where its engine can.
struct BrowserDownloadMenu: Equatable {
    // MARK: - Types

    enum Entry: Hashable {
        case send(BrowserUtilityDownloadDestination)
        case pause
        case resume
        case cancel
        case allow
        case remove
        case moveToTrash

        var title: LocalizedStringResource {
            switch self {
            case .send(let destination): destination.title
            case .pause: DownloadRowAction.pause.title
            case .resume: DownloadRowAction.resume.title
            case .cancel: DownloadRowAction.cancel.title
            case .allow: DownloadRowAction.retry.title
            case .remove: "Remove from List"
            case .moveToTrash: "Move to Trash"
            }
        }

        var symbol: String {
            switch self {
            case .send(let destination): destination.symbol
            case .pause: DownloadRowAction.pause.symbol
            case .resume: DownloadRowAction.resume.symbol
            case .cancel: DownloadRowAction.cancel.symbol
            case .allow: DownloadRowAction.retry.symbol
            case .remove: "minus.circle"
            case .moveToTrash: "trash"
            }
        }

        /// Moving a file to the Trash is the one entry that touches the file.
        var isDestructive: Bool { self == .moveToTrash }

        /// What choosing the entry asks of download `itemID`.
        func action(for itemID: UUID) -> BrowserUtilityDownloadAction {
            switch self {
            case .send(let destination): .open(itemID, destination)
            case .pause: .pause(itemID)
            case .resume: .resume(itemID)
            case .cancel: .cancel(itemID)
            case .allow: .retry(itemID)
            case .remove: .clear(itemID)
            case .moveToTrash: .moveToTrash(itemID)
            }
        }
    }

    // MARK: - Variables

    let groups: [[Entry]]

    // MARK: - Initializers

    /// The menu of `item`, whose finished file may be missing, in a shell
    /// that sends finished files to `destinations` and may offer the Trash.
    init(
        item: DownloadState,
        destinations: [BrowserUtilityDownloadDestination],
        isFileMissing: Bool,
        offersMoveToTrash: Bool
    ) {
        let engine: [Entry] = item.canPause ? [.pause] : item.canResume ? [.resume] : []
        if item.phase.isLive {
            groups = [engine + [.cancel]]
        } else if item.phase.canRetry {
            groups = [[.allow], [.remove]]
        } else if item.phase.isComplete, !isFileMissing {
            let leaving: [Entry] = offersMoveToTrash ? [.remove, .moveToTrash] : [.remove]
            groups = [destinations.map(Entry.send), leaving].filter { !$0.isEmpty }
        } else {
            groups = [engine, [.remove]].filter { !$0.isEmpty }
        }
    }
}
