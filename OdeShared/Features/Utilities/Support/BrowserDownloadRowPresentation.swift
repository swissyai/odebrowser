import Foundation

struct BrowserDownloadRowPresentation: Sendable {
    /// The narrowest row that keeps the status and transfer metrics on one line.
    static let inlineMinimumWidth: CGFloat = 360
    /// The side of a row's file icon or progress ring, and the space after it.
    static let iconSide: CGFloat = 28
    static let iconSpacing: CGFloat = 10

    let bytesReceived: Int64
    let totalBytes: Int64?
    let progress: Double
    let bytesPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?
    let statusText: BrowserUtilityText
    let statusNeedsAttention: Bool
    let showsTransferMetrics: Bool
    let showsStatusAlongsideMetrics: Bool
    /// The file is saved in full, so its size says everything the row needs.
    let isComplete: Bool

    /// `fileIsMissing` says a finished file has since been moved or
    /// deleted, which the row then says instead of its size.
    static func resolve(
        item: DownloadState,
        fileIsMissing: Bool = false
    ) -> BrowserDownloadRowPresentation {
        let telemetry = item.telemetry
        let isActivelyDownloading =
            item.phase.isTransferring
            && !telemetry.isPaused
        let statusText: BrowserUtilityText =
            if item.phase.isTransferring && telemetry.isPaused {
                .localized("Paused")
            } else if fileIsMissing {
                .localized("Moved or deleted")
            } else {
                status(of: item)
            }
        let showsTransferMetrics =
            !fileIsMissing
            && (telemetry.bytesReceived > 0
                || telemetry.totalBytes != nil
                || item.phase.isComplete)
        return BrowserDownloadRowPresentation(
            bytesReceived: telemetry.bytesReceived,
            totalBytes: telemetry.totalBytes,
            progress: item.progress,
            bytesPerSecond: isActivelyDownloading
                ? telemetry.bytesPerSecond
                : nil,
            estimatedTimeRemaining: isActivelyDownloading
                ? telemetry.estimatedTimeRemaining
                : nil,
            statusText: statusText,
            statusNeedsAttention: item.phase.needsAttention,
            showsTransferMetrics: showsTransferMetrics,
            showsStatusAlongsideMetrics: showsTransferMetrics
                && !isActivelyDownloading
                && !item.phase.isComplete,
            isComplete: item.phase.isComplete
        )
    }

    /// The phase's title, or for a phase without one, why the record stopped
    /// in its localized words, else its own message. Search matches it
    /// without waiting for transfer telemetry.
    static func status(of item: DownloadState) -> BrowserUtilityText {
        if let title = item.phase.title { return .localized(title) }
        if let failure = item.failure { return .localized(failure.message) }
        return .verbatim(item.message ?? "")
    }

    /// The size of a finished file: what arrived, or what was announced
    /// when nothing was counted.
    var completedSize: Int64 {
        bytesReceived > 0 ? bytesReceived : totalBytes ?? 0
    }

    /// A time left, in its largest unit only, so a row's metrics stay on one
    /// line in a narrow sidebar.
    static func timeRemaining(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    var hasSecondaryTransferMetrics: Bool {
        bytesPerSecond != nil
            || estimatedTimeRemaining != nil
            || showsStatusAlongsideMetrics
    }

    /// How a row this wide lays the presentation out.
    func layout(
        availableWidth: CGFloat,
        usesAccessibilityTextSize: Bool
    ) -> BrowserDownloadRowLayout {
        // Without metrics the status is the only line; a second would repeat it.
        guard hasSecondaryTransferMetrics else {
            return .singleLine
        }
        guard !usesAccessibilityTextSize,
            !statusNeedsAttention,
            availableWidth >= Self.inlineMinimumWidth
        else {
            return .stacked
        }
        return .inline
    }
}

enum BrowserDownloadRowLayout: Equatable, Sendable {
    case singleLine
    case inline
    case stacked
}
