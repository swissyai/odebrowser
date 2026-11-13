import Foundation
import XCTest

@testable import Ode

final class BrowserUtilityListTests: XCTestCase {
    func testDownloadProgressDoesNotRestartUtilitySectionPreparation() {
        let id = UUID()
        let profileID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: profileID
        )
        let createdAt = Date.now
        let initial = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Ode.dmg", progress: 0.1,
            phase: .downloading)
        let progressed = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Ode.dmg", progress: 0.9,
            phase: .downloading)
        let finished = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Ode.dmg", progress: 0.9,
            phase: .finished)

        let initialRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [initial],
            searchText: "",
            filter: .all
        )
        let progressRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [progressed],
            searchText: "",
            filter: .all
        )
        let finishedRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [finished],
            searchText: "",
            filter: .all
        )

        XCTAssertEqual(initialRequest, progressRequest)
        XCTAssertNotEqual(initialRequest, finishedRequest)
    }

    func testUtilityPreparationIdentityIncludesTheExactSpaceProfileAssignment() {
        let spaceID = UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                0x4C, 0x49, 0x54, 0x59, 0x53, 0x50, 0x41, 0x43
            ))
        let first = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x31
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        let replacement = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x32
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        XCTAssertNotEqual(first, replacement)
        XCTAssertFalse(first.hasSamePresentationOwnership(as: replacement))
    }

    func testDownloadReconciliationUsesLiveProgressWithoutSynthesizingRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.1,
            phase: .downloading
        )
        let current = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.82,
            phase: .downloading
        )
        let newlyArrived = utilityDownload(
            id: identifier(0x65),
            profileID: context.assignment.profileID,
            progress: 0.3,
            phase: .downloading
        )

        let sections = BrowserUtilityListReconciliation.sections(
            preparedSections: [context.section(prepared)],
            surface: .downloads,
            assignment: context.assignment,
            downloads: [current, newlyArrived],
            searchText: "",
            filter: .all
        )

        let item = try XCTUnwrap(sections.first?.items.first)
        guard case .download(let download) = item else {
            return XCTFail("Expected a reconciled download")
        }
        XCTAssertEqual(download.id, context.itemID)
        XCTAssertEqual(download.progress, 0.82)
        XCTAssertEqual(sections.flatMap(\.items).count, 1)
    }

    func testDownloadReconciliationImmediatelyAppliesCurrentFilterState() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.8,
            phase: .downloading
        )
        let finished = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 1,
            phase: .finished
        )
        let preparedSections = [context.section(prepared)]

        XCTAssertTrue(
            BrowserUtilityListReconciliation.sections(
                preparedSections: preparedSections,
                surface: .downloads,
                assignment: context.assignment,
                downloads: [finished],
                searchText: "",
                filter: .downloadsInProgress
            ).isEmpty
        )

        let allSections = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [finished],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(allSections.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected a current download")
        }
        XCTAssertEqual(current.phase, .finished)
    }

    func testDownloadReconciliationDropsRemovedAndForeignProfileRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.2,
            phase: .downloading
        )
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.9,
            phase: .finished
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.4,
            phase: .downloading
        )
        let preparedSections = [context.section(prepared)]

        for current in [[], [foreign]] {
            XCTAssertTrue(
                BrowserUtilityListReconciliation.sections(
                    preparedSections: preparedSections,
                    surface: .downloads,
                    assignment: context.assignment,
                    downloads: current,
                    searchText: "",
                    filter: .all
                ).isEmpty
            )
        }

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, foreign],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(reconciled.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected the exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.4)
    }

    func testDownloadReconciliationEmitsDuplicatePreparedIDsOnce() throws {
        let context = utilityDownloadContext()
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.1,
            phase: .downloading
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.7,
            phase: .downloading
        )
        let preparedSections = [
            context.section(foreign),
            context.section(exact),
        ]

        let request = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: context.assignment,
            archivedTabs: [],
            history: [],
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        XCTAssertEqual(request.downloads.map(\.id), [context.itemID])
        XCTAssertEqual(request.downloads.first?.profileID, context.assignment.profileID)

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        let items = reconciled.flatMap(\.items)
        XCTAssertEqual(items.count, 1)
        guard case .download(let current) = try XCTUnwrap(items.first) else {
            return XCTFail("Expected one exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.7)
    }

    func testUtilityPreparationRefreshesAtTheNextRelevantBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-08-08T00:00:00Z"))
        let visitDate = try XCTUnwrap(
            formatter.date(from: "2026-08-01T15:00:00Z")
        )
        let entry = HistoryEntryState(
            id: identifier(0x67),
            url: "file:///crest-preview/history",
            title: "History",
            firstVisitedAt: visitDate,
            lastVisitedAt: visitDate,
            visitCount: 1
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [entry],
            downloads: [],
            searchText: "",
            filter: .historyPastWeek
        )

        XCTAssertEqual(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: request,
                now: now,
                calendar: calendar
            ),
            try XCTUnwrap(formatter.date(from: "2026-08-08T15:00:00Z"))
        )

        let emptyRequest = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        XCTAssertNil(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: emptyRequest,
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testDownloadRecordsRetainTheTimeUsedForListGrouping() {
        let center = BrowserDownloadCenter()
        let createdAt = Date(timeIntervalSince1970: 1_786_084_200)

        _ = center.begin(
            profileID: UUID(),
            filename: "crest.dmg",
            createdAt: createdAt
        )

        XCTAssertEqual(center.items.first?.createdAt, createdAt)
    }

    func testUtilitySectionsArePreparedAwayFromTheRenderPass() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")
        )
        let today = HistoryEntryState(
            id: UUID(),
            url: "https://example.com/today",
            title: "Today",
            firstVisitedAt: now,
            lastVisitedAt: now,
            visitCount: 1
        )
        let yesterdayDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: now)
        )
        let yesterday = HistoryEntryState(
            id: UUID(),
            url: "https://example.com/yesterday",
            title: "Yesterday",
            firstVisitedAt: yesterdayDate,
            lastVisitedAt: yesterdayDate,
            visitCount: 1
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: UUID(),
                profileID: UUID()
            ),
            archivedTabs: [],
            history: [yesterday, today],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = await Task.detached(priority: .userInitiated) {
            BrowserUtilityListPreparation.sections(
                for: request,
                now: now,
                calendar: calendar
            )
        }.value

        XCTAssertEqual(
            sections.map {
                localized($0.timeframe.title, locale: Locale(identifier: "en"))
            },
            ["Today", "1 day ago"]
        )
        XCTAssertEqual(sections.flatMap(\.items).count, 2)
    }

    @MainActor
    func testCommonListTriggerCanRouteANewDownloadNotificationToDownloads() {
        let presentation = BrowserUtilityPresentationState()

        presentation.toggleSwitcher(for: nil, hasNewDownloads: true)

        XCTAssertTrue(presentation.isSwitcherExpanded)
        XCTAssertEqual(presentation.surface, .downloads)
    }

    @MainActor
    func testCommonListTriggerRestoresTheSpacesChosenSurfaceAcrossPresentationStates() throws {
        let suiteName = "crest.tests.utility-presentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = BrowserUtilityPresentationState(defaults: defaults)
        let spaceID = UUID()

        first.chooseTriggerSurface(.history, for: spaceID)

        let restored = BrowserUtilityPresentationState(defaults: defaults)
        restored.toggleSwitcher(for: spaceID)

        XCTAssertTrue(restored.isSwitcherExpanded)
        XCTAssertEqual(restored.surface, .history)
    }

    /// Section navigation, not only a preference menu, remembers each Space's last list across windows.
    @MainActor
    func testLibraryNavigationRemembersEachSpaceWithoutOverwritingAnotherWindowsChoice() throws {
        let suiteName = "ode.tests.library-navigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = BrowserUtilityPresentationState(defaults: defaults)
        let second = BrowserUtilityPresentationState(defaults: defaults)
        let firstSpace = UUID()
        let secondSpace = UUID()

        first.present(.history, for: firstSpace)
        second.present(.archive, for: secondSpace)
        first.present(.downloads, for: firstSpace)
        first.dismiss()
        first.toggleSwitcher(for: firstSpace)

        XCTAssertEqual(first.surface, .downloads)
        XCTAssertEqual(second.surface, .archive)
        let restored = BrowserUtilityPresentationState(defaults: defaults)
        XCTAssertEqual(restored.triggerSurface(for: firstSpace), .downloads)
        XCTAssertEqual(restored.triggerSurface(for: secondSpace), .archive)
        first.toggleSwitcher(for: firstSpace)
        XCTAssertNil(first.surface)
        restored.toggleSwitcher(for: secondSpace, hasNewDownloads: true)
        XCTAssertEqual(restored.surface, .downloads)
        XCTAssertEqual(restored.triggerSurface(for: secondSpace), .downloads)
    }

    /// Switching sections or returning to tabs discards input intended for the old search field.
    @MainActor
    func testLibraryNavigationCancelsOldSearchFocusWithoutCancelingTheCurrentRequest() {
        let presentation = BrowserUtilityPresentationState()
        presentation.present(.downloads)
        presentation.focusSearch()
        let oldRequest = presentation.searchFocusRequest
        presentation.present(.history)
        XCTAssertFalse(presentation.consumeSearchFocusRequest(oldRequest, for: .downloads))
        XCTAssertFalse(presentation.consumeSearchFocusRequest(oldRequest, for: .history))

        presentation.focusSearch()
        let currentRequest = presentation.searchFocusRequest
        presentation.dismiss(.downloads)
        XCTAssertEqual(presentation.surface, .history)
        XCTAssertTrue(presentation.consumeSearchFocusRequest(currentRequest, for: .history))
        XCTAssertFalse(presentation.consumeSearchFocusRequest(currentRequest, for: .history))
        presentation.focusSearch()
        let dismissedRequest = presentation.searchFocusRequest
        presentation.dismiss()
        presentation.present(.history)
        XCTAssertFalse(presentation.consumeSearchFocusRequest(dismissedRequest, for: .history))
    }

    /// Find can be requested before a sidebar mounts, but a different Space/profile cannot consume it.
    @MainActor
    func testPendingLibrarySearchFocusBelongsToItsExactSpaceProfile() {
        let presentation = BrowserUtilityPresentationState()
        let source = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        presentation.present(.history)
        presentation.focusSearch(matching: source)
        let request = presentation.searchFocusRequest
        let otherSpace = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: source.profileID)
        let replacementProfile = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: UUID())

        XCTAssertFalse(presentation.consumeSearchFocusRequest(request, for: .history, matching: otherSpace))
        XCTAssertFalse(presentation.consumeSearchFocusRequest(request, for: .history, matching: replacementProfile))
        XCTAssertTrue(presentation.consumeSearchFocusRequest(request, for: .history, matching: source))
    }

    func testDownloadNotificationUsesTheNewestActiveTransferProgress() throws {
        let profileID = identifier(0x70)
        let older = DownloadState.fixture(
            id: identifier(0x71), profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: 100),
            filename: "older.zip", progress: 0.8, phase: .downloading)
        let newest = DownloadState.fixture(
            id: identifier(0x72), profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: 200),
            filename: "newest.pdf", progress: 0.35, phase: .downloading)

        XCTAssertEqual(
            try XCTUnwrap(
                [older, newest].notificationProgress
            ),
            0.35,
            accuracy: 0.001
        )
    }

    func testFinishedDownloadRowRevealsTheFileInFinder() {
        XCTAssertEqual(
            BrowserUtilityDownloadDestination.primary(
                for: .finished,
                among: [.open, .revealInFinder]
            ),
            .revealInFinder
        )
        XCTAssertNil(
            BrowserUtilityDownloadDestination.primary(
                for: .downloading,
                among: [.open, .revealInFinder]
            )
        )
    }

    @MainActor
    func testArchivePreparationSortsByTheTimeTheTabWasClosed() throws {
        let now = Date(timeIntervalSinceReferenceDate: 900)
        let older = ArchivedTabState.Seed(
            tab: TabState.Seed(
                id: identifier(0x73),
                title: "Older",
                url: URL(string: "https://example.com/older"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 800)
            ),
            archivedAt: Date(timeIntervalSinceReferenceDate: 850),
            reason: .closed
        )
        let newer = ArchivedTabState.Seed(
            tab: TabState.Seed(
                id: identifier(0x74),
                title: "Newer",
                url: URL(string: "https://example.com/newer"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            archivedAt: now,
            reason: .autoCleanup
        )
        let space = SpaceState.Seed(
            id: identifier(0x61), profileID: identifier(0x62), name: "Archive",
            symbol: "archivebox", accent: .indigo, folders: [], tabs: [], archivedTabs: [older, newer])
        let store = BrowserStore(seed: SessionState.Seed(spaces: [space]), showing: space.id)
        let request = BrowserUtilityListRequest(
            surface: .archive,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: try XCTUnwrap(store.spaceModel(space.id)?.archive.entries),
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = BrowserUtilityListPreparation.sections(
            for: request,
            now: now,
            calendar: .current
        )

        XCTAssertEqual(
            sections.flatMap(\.items).compactMap { item -> UUID? in
                guard case .archive(let archived) = item else { return nil }
                return archived.tab.id
            },
            [newer.id, older.id]
        )
    }

    func testHistoryGroupingKeepsFilteredMembershipWithoutDuplicates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            HistoryEntryState(
                url: URL(string: "https://www.example.com/a")!, title: "Guide", firstVisitedAt: now, lastVisitedAt: now),
            HistoryEntryState(
                url: URL(string: "https://example.com/b")!, title: "Guide", firstVisitedAt: now, lastVisitedAt: now),
            HistoryEntryState(
                url: URL(string: "https://old.example/c")!, title: "Guide",
                firstVisitedAt: now.addingTimeInterval(-864_000),
                lastVisitedAt: now.addingTimeInterval(-864_000)),
        ]
        var request = BrowserUtilityListRequest(
            surface: .history, assignment: utilityDownloadContext().assignment, archivedTabs: [], history: entries,
            downloads: [], searchText: "Guide", filter: .historyToday)
        let timed = BrowserUtilityListPreparation.sections(for: request, now: now)
        request.historyGrouping = .site
        let grouped = BrowserUtilityListPreparation.sections(for: request, now: now)
        XCTAssertEqual(Set(grouped.flatMap(\.items).map(\.id)), Set(timed.flatMap(\.items).map(\.id)))
        XCTAssertEqual(grouped.flatMap(\.items).count, 2)
        XCTAssertEqual(grouped.count, 1)
    }

    func testCoreHistoryPlacesSkipTheSearchAndGroupNewestFirstByTimeOrSite() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        func place(_ url: String, hoursAgo: Double) -> HistoryPlace {
            let visited = now.addingTimeInterval(-hoursAgo * 3_600)
            return HistoryPlace(url: url, title: "Page", firstVisitedAt: visited, lastVisitedAt: visited, visitCount: 1)
        }
        let places = [
            place("https://Docs.Example.com/a", hoursAgo: 30),
            place("https://www.docs.example.com/b", hoursAgo: 1),
            place("notes", hoursAgo: 2),
            place("https://other.example/c", hoursAgo: 3),
        ]
        var request = BrowserUtilityListRequest(
            surface: .history, assignment: utilityDownloadContext().assignment, archivedTabs: [], history: [],
            downloads: [], searchText: "matches none of them", filter: .all)
        func urls(_ section: BrowserUtilityListSection) -> [String] {
            section.items.compactMap { item in
                guard case .history(let place) = item else { return nil }
                return place.url
            }
        }

        let timed = BrowserUtilityListPreparation.sections(
            for: request, now: now, calendar: calendar, history: places)
        XCTAssertEqual(
            timed.map(urls),
            [
                ["https://www.docs.example.com/b", "notes", "https://other.example/c"],
                ["https://Docs.Example.com/a"],
            ])
        XCTAssertEqual(
            timed.map(\.timeframe),
            [
                BrowserUtilityTimeSection(date: places[1].lastVisitedAt, now: now, calendar: calendar),
                BrowserUtilityTimeSection(date: places[0].lastVisitedAt, now: now, calendar: calendar),
            ])
        XCTAssertTrue(BrowserUtilityListPreparation.sections(for: request, now: now, calendar: calendar).isEmpty)

        request.historyGrouping = .site
        let bySite = BrowserUtilityListPreparation.sections(
            for: request, now: now, calendar: calendar, history: places)
        XCTAssertEqual(bySite.map(\.site), ["docs.example.com", "notes", "other.example"])
        XCTAssertEqual(
            bySite.map(urls),
            [
                ["https://www.docs.example.com/b", "https://Docs.Example.com/a"],
                ["notes"],
                ["https://other.example/c"],
            ])
        XCTAssertEqual(
            Set(bySite.map(\.timeframe)), [BrowserUtilityTimeSection(date: now, now: now, calendar: calendar)])
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func utilityDownloadContext() -> (
        assignment: BrowserSpaceRuntimeAssignment,
        itemID: UUID,
        section: (DownloadState) -> BrowserUtilityListSection
    ) {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: identifier(0x61),
            profileID: identifier(0x62)
        )
        let now = Date(timeIntervalSinceReferenceDate: 807_969_600)
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        let timeframe = BrowserUtilityTimeSection(
            date: now,
            now: now,
            calendar: calendar
        )
        return (
            assignment,
            identifier(0x63),
            { item in
                BrowserUtilityListSection(
                    timeframe: timeframe,
                    items: [.download(item)]
                )
            }
        )
    }

    private func utilityDownload(
        id: UUID,
        profileID: UUID,
        progress: Double,
        phase: DownloadPhase
    ) -> DownloadState {
        DownloadState.fixture(
            id: id,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 807_969_600),
            filename: "Ode.dmg",
            destination: URL(filePath: "/crest-preview/Ode.dmg"),
            progress: progress,
            phase: phase
        )
    }

    private func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }
}
