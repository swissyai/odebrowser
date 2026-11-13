import Foundation
import SwiftUI

// MARK: - Types

private struct BrowserUtilityPreparationID: Equatable, Sendable {
    let request: BrowserUtilityListRequest
    let retry: Int
}

struct BrowserUtilityListContent: View {
    // MARK: - Variables

    let surface: BrowserUtilitySurface
    let space: SpaceModel
    let downloads: [DownloadState]
    let searchText: String
    let filter: BrowserUtilityListFilter
    let actions: BrowserUtilityListActions
    var dismissOnBlankSpace: (() -> Void)? = nil
    /// The images the listed tabs wear, as the read model holds them.
    var favicons: FaviconAssets? = nil
    var preparationClock: BrowserUtilityListClock = .live
    var preparationCalendar: Calendar = .autoupdatingCurrent

    @Environment(\.browserSpaceContentIsLocked) private var isLocked
    @State private var preparedRequest: BrowserUtilityListRequest?
    @State private var sections: [BrowserUtilityListSection] = []
    /// How many history addresses the list reads, which grows by a page each
    /// time the person scrolls to the end while more follow.
    @State private var historyLimit = BrowserHistoryReader.pageSize
    @State private var hasMoreHistory = false
    @State private var historyReadFailed = false
    @State private var historyRetry = 0
    @State private var isPreparingHistory = false
    @State private var historyGrouping: BrowserHistoryGrouping = .time

    var body: some View {
        VStack(spacing: 0) {
            if surface == .history {
                Picker(String(localized: "Group History"), selection: $historyGrouping) {
                    ForEach(BrowserHistoryGrouping.all) { grouping in
                        Text(grouping.title).tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OdeSpacing.small)
                .padding(.vertical, OdeSpacing.extraSmall)
            }
            if historyReadFailed {
                ContentUnavailableView {
                    Label(String(localized: "History couldn’t be loaded"), systemImage: "exclamationmark.triangle")
                } description: {
                    EmptyView()
                } actions: {
                    Button(String(localized: "Retry")) { historyRetry += 1 }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingHistory)
                        .accessibilityIdentifier("browser.history.retry")
                }
            } else {
                presentation
            }
        }
        .environment(\.browserFavicons, favicons)
        .accessibilityIdentifier(BrowserUtilityAccessibilityID.list(surface))
        .task(id: BrowserUtilityPreparationID(request: request, retry: historyRetry)) {
            await refreshSections(for: request)
        }
        .onChange(of: searchText) { historyLimit = BrowserHistoryReader.pageSize }
        .onChange(of: space.id) { historyLimit = BrowserHistoryReader.pageSize }
    }

    private var presentation: some View {
        BrowserUtilityListPresentation(
            surface: surface,
            searchText: searchText,
            filter: filter,
            presentationRequest: preparedPresentationRequest,
            sections: sections,
            downloads: isLocked ? [] : downloads,
            actions: actions,
            dismissOnBlankSpace: dismissOnBlankSpace,
            reachEnd: reachEnd
        )
    }

    /// Reads another page of history once the last row shows, while more follow.
    private var reachEnd: (() -> Void)? {
        guard hasMoreHistory else { return nil }
        return { historyLimit += BrowserHistoryReader.pageSize }
    }

    private var request: BrowserUtilityListRequest {
        var request = BrowserUtilityListRequest(
            surface: surface,
            space: space,
            downloads: downloads,
            searchText: searchText,
            filter: filter,
            isUnlocked: !isLocked,
            historyLimit: historyLimit,
            historyRevision: surface == .history ? actions.readHistory?.revision ?? 0 : 0
        )
        request.historyGrouping = historyGrouping
        return request
    }

    private var preparedPresentationRequest: BrowserUtilityListRequest? {
        guard let preparedRequest,
            preparedRequest.hasSamePresentationOwnership(as: request)
        else { return nil }
        return preparedRequest
    }

    // MARK: - Actions - Preparation

    @MainActor
    private func refreshSections(for request: BrowserUtilityListRequest) async {
        while !Task.isCancelled {
            let now = preparationClock.currentDate()
            await prepareSections(for: request, now: now)
            guard preparationClock.refreshesOverTime,
                !Task.isCancelled,
                let deadline = BrowserUtilityListPreparation.nextRefreshDate(
                    for: request,
                    now: now,
                    calendar: preparationCalendar
                )
            else { return }

            let delay = max(deadline.timeIntervalSinceNow, 0.1)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func prepareSections(
        for request: BrowserUtilityListRequest,
        now: Date
    ) async {
        if let preparedRequest,
            preparedRequest.searchText != request.searchText
        {
            try? await Task.sleep(
                for: BrowserUtilityListPreparation.searchDebounce
            )
            guard !Task.isCancelled else { return }
        }
        let calendar = preparationCalendar
        let reader = request.readsHistory ? actions.readHistory : nil
        isPreparingHistory = reader != nil
        defer { isPreparingHistory = false }
        let preparation = Task.detached(priority: .userInitiated) {
            let history = try reader?.places(
                in: request.assignment.spaceID,
                matching: request.searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                limit: request.historyLimit
            )
            let sections = BrowserUtilityListPreparation.sections(
                for: request,
                now: now,
                calendar: calendar,
                history: history?.places ?? (reader == nil ? nil : [])
            )
            return (sections, history?.hasMore ?? false)
        }
        do {
            let (preparedSections, hasMore) = try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: {
                preparation.cancel()
            }
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                sections = preparedSections
                preparedRequest = request
                hasMoreHistory = hasMore
                historyReadFailed = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            historyReadFailed = true
            DiagnosticLog.history.error("History could not be read: \(DiagnosticLog.describe(error)).")
        }
    }

}

#Preview("History Results", traits: .fixedLayout(width: 360, height: 420)) {
    if let space = BrowserUtilityListPreviewFixture.historySpaceModel {
        BrowserUtilityListContent(
            surface: .history,
            space: space,
            downloads: [],
            searchText: "",
            filter: .all,
            actions: BrowserUtilityListActions(),
            preparationClock: .fixed(
                BrowserUtilityListPreviewFixture.referenceDate
            ),
            preparationCalendar: BrowserUtilityListPreviewFixture.fixedCalendar
        )
    }
}
