import Foundation
import XCTest

@testable import Ode

/// The namespace this file's fixed identifiers share.
private let idNamespace = "SIDEBARUTILITY"

/// The shared coordinator's behaviour, driven through a recording platform port
/// so the guards are tested apart from what either shell does afterwards. The
/// windowed shell's own binding is covered at the bottom; the compact shell's
/// is covered by `MobileBrowserSidebarUtilityCoordinatorTests`.
@MainActor
final class BrowserSidebarUtilityCoordinatorTests: XCTestCase {
    func testExactSelectedAssignmentRestoresArchiveAndOpensHistory() throws {
        let context = makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let entry = try XCTUnwrap(context.browser.spaceModel(context.source.id)?.history.entries.first)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(HistoryPlace(entry), assignment)

        let source = try XCTUnwrap(
            context.browser.spaceModel(context.source.id)
        )
        XCTAssertFalse(source.archive.contains(tabID: context.archived.id))
        XCTAssertTrue(source.tabs.contains(context.archived.id))
        XCTAssertEqual(port.restoredTabs, [context.archived.id])
        XCTAssertEqual(port.openedURLs.map(\.absoluteString), [context.history.url])
    }

    func testHistoryCanBeKeptWithoutNavigatingOrRemovingTheVisit() throws {
        let context = makeContext(historyURL: URL(string: "http://127.0.0.1/history")!)
        let port = RecordedPlatformActions()
        let actions = makeCoordinator(context, port: port).actions
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let entry = HistoryPlace(context.history)
        let selected = context.browser.selectedTabID(in: context.source.id)
        actions.keepHistoryEntry?(entry, .saved, assignment)
        actions.keepHistoryEntry?(entry, .pinned, assignment)
        let space = try XCTUnwrap(context.browser.spaceModel(context.source.id))
        let kept = space.tabs.models.filter { $0.url == entry.url }
        XCTAssertEqual(Set(kept.map(\.placement)), [.saved, .pinned])
        XCTAssertTrue(kept.allSatisfy { $0.savedURL == entry.url })
        XCTAssertEqual(context.browser.selectedTabID(in: context.source.id), selected)
        XCTAssertEqual(space.history.entries.map(\.url), [entry.url])
        XCTAssertTrue(port.openedURLs.isEmpty)
        actions.removeHistoryEntry?(entry, assignment)
        XCTAssertTrue(space.history.entries.isEmpty)
        XCTAssertEqual(space.tabs.models.filter { $0.url == entry.url }.count, 2)
    }

    func testKeepingAnArchivedTabDoesNotNavigateOrChangeItsIdentity() throws {
        for placement in [TabPlacement.saved, .pinned] {
            let context = makeContext()
            let port = RecordedPlatformActions()
            let actions = makeCoordinator(context, port: port).actions
            let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
            let selected = context.browser.shownTab?.id
            actions.keepArchivedTab?(context.archived.id, placement, assignment)
            let space = try XCTUnwrap(context.browser.spaceModel(context.source.id))
            let kept = try XCTUnwrap(space.tabs.model(context.archived.id))
            XCTAssertEqual(kept.placement, placement)
            XCTAssertFalse(space.archive.contains(tabID: context.archived.id))
            XCTAssertEqual(context.browser.shownTab?.id, selected)
            XCTAssertTrue(port.restoredTabs.isEmpty)
            XCTAssertTrue(port.openedURLs.isEmpty)
        }
    }

    /// A retained Library header cannot change or dismiss the newly selected Space's list.
    func testLibraryNavigationRequiresTheExactSelectedUnlockedAssignment() {
        let context = makeContext()
        let coordinator = makeCoordinator(context, port: RecordedPlatformActions())
        let presentation = BrowserUtilityPresentationState()
        let source = BrowserSpaceRuntimeAssignment(space: context.source)
        let destination = BrowserSpaceRuntimeAssignment(space: context.destination)
        let selectedTabID = context.browser.shownTab?.id

        coordinator.selectSurface(.downloads, matching: source, in: presentation)
        coordinator.selectSurface(.history, matching: source, in: presentation)
        XCTAssertEqual(presentation.surface, .history)
        XCTAssertEqual(presentation.triggerSurface(for: source.spaceID), .history)
        XCTAssertEqual(context.browser.shownTab?.id, selectedTabID)

        context.browser.selectSpace(context.destination.id)
        coordinator.selectSurface(.archive, matching: destination, in: presentation)
        coordinator.selectSurface(.downloads, matching: source, in: presentation)
        coordinator.dismissSurface(.archive, matching: source, in: presentation)
        XCTAssertEqual(presentation.surface, .archive)
        XCTAssertEqual(presentation.triggerSurface(for: source.spaceID), .history)

        replaceProfile(of: context.destination, in: context.browser)
        coordinator.selectSurface(.history, matching: destination, in: presentation)
        coordinator.dismissSurface(.archive, matching: destination, in: presentation)
        XCTAssertEqual(presentation.surface, .archive)

        let protected = makeContext(isProtected: true)
        let lockedCoordinator = makeCoordinator(protected, port: RecordedPlatformActions())
        let locked = BrowserSpaceRuntimeAssignment(space: protected.source)
        lockedCoordinator.selectSurface(.downloads, matching: locked, in: presentation)
        lockedCoordinator.dismissSurface(.archive, matching: locked, in: presentation)
        XCTAssertEqual(presentation.surface, .archive)
    }

    func testCapturedUtilityActionsRejectSelectionAndProfileChanges() throws {
        try assertActionsAreRejected { context in
            context.browser.selectSpace(context.destination.id)
        }
        try assertActionsAreRejected { context in
            self.replaceProfile(of: context.source, in: context.browser)
        }
    }

    func testCapturedUtilityActionsRejectLockedAndDeletingSpaces() throws {
        try assertActionsAreRejected(
            context: makeContext(isProtected: true),
            mutation: { _ in }
        )

        let deletingContext = makeContext()
        XCTAssertTrue(
            deletingContext.browser.family.beginDeletingSpace(
                deletingContext.source.id
            )
        )
        defer {
            deletingContext.browser.family.finishDeletingSpace(
                deletingContext.source.id
            )
        }
        try assertActionsAreRejected(context: deletingContext, mutation: { _ in })
    }

    /// Each download action reaches the shell's port with the item the policy
    /// approved, and a captured action whose Space has moved on reaches nothing.
    func testDownloadActionsReachThePlatformPortForOwnedItemsOnly() {
        let context = makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let itemID = context.downloadItemID

        coordinator.actions.performDownloadAction(
            .open(itemID, .revealInFinder),
            assignment
        )
        coordinator.actions.performDownloadAction(.cancel(itemID), assignment)
        coordinator.actions.performDownloadAction(.clear(itemID), assignment)

        XCTAssertEqual(port.openedDownloads.map { $0.item.id }, [itemID])
        XCTAssertEqual(port.openedDownloads.map { $0.destination }, [.revealInFinder])
        XCTAssertEqual(port.canceledDownloads, [itemID])
        XCTAssertEqual(port.clearedDownloads, [itemID])

        context.browser.selectSpace(context.destination.id)
        coordinator.actions.performDownloadAction(
            .open(itemID, .revealInFinder),
            assignment
        )
        coordinator.actions.performDownloadAction(.cancel(itemID), assignment)
        coordinator.actions.performDownloadAction(.clear(itemID), assignment)

        XCTAssertEqual(port.openedDownloads.count, 1)
        XCTAssertEqual(port.canceledDownloads, [itemID])
        XCTAssertEqual(port.clearedDownloads, [itemID])
    }

    func testDownloadPolicyRequiresExactSelectedUnlockedProfileOwnership() {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let exactItem = downloadItem(profileID: assignment.profileID, id: UUID.fixed(20, namespace: idNamespace))
        let wrongProfileItem = downloadItem(
            profileID: UUID.fixed(21, namespace: idNamespace),
            id: exactItem.id
        )
        let action = BrowserUtilityDownloadAction.clear(exactItem.id)

        XCTAssertEqual(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [exactItem] }),
            exactItem
        )
        XCTAssertNil(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [wrongProfileItem] })
        )

        context.browser.selectSpace(context.destination.id)
        XCTAssertNil(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [exactItem] })
        )

        let lockedContext = makeContext(isProtected: true)
        let lockedAssignment = BrowserSpaceRuntimeAssignment(
            space: lockedContext.source
        )
        let lockedItem = downloadItem(
            profileID: lockedAssignment.profileID,
            id: UUID.fixed(22, namespace: idNamespace)
        )
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(lockedItem.id).downloadItem(
                matching: lockedAssignment, in: lockedContext.browser, accessController: lockedContext.access,
                itemsForProfile: { _ in [lockedItem] })
        )

        let deletingContext = makeContext()
        let deletingAssignment = BrowserSpaceRuntimeAssignment(
            space: deletingContext.source
        )
        let deletingItem = downloadItem(
            profileID: deletingAssignment.profileID,
            id: UUID.fixed(23, namespace: idNamespace)
        )
        XCTAssertTrue(
            deletingContext.browser.family.beginDeletingSpace(
                deletingContext.source.id
            )
        )
        defer {
            deletingContext.browser.family.finishDeletingSpace(
                deletingContext.source.id
            )
        }
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(deletingItem.id).downloadItem(
                matching: deletingAssignment, in: deletingContext.browser, accessController: deletingContext.access,
                itemsForProfile: { _ in [deletingItem] })
        )

        let replacementContext = makeContext()
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            space: replacementContext.source
        )
        let replacementItem = downloadItem(
            profileID: replacementAssignment.profileID,
            id: UUID.fixed(24, namespace: idNamespace)
        )
        replaceProfile(
            of: replacementContext.source,
            in: replacementContext.browser
        )
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(replacementItem.id).downloadItem(
                matching: replacementAssignment, in: replacementContext.browser,
                accessController: replacementContext.access, itemsForProfile: { _ in [replacementItem] })
        )
    }

    private func assertActionsAreRejected(
        context: Context? = nil,
        mutation: (Context) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = context ?? makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let entry = try XCTUnwrap(context.browser.spaceModel(context.source.id)?.history.entries.first)
        mutation(context)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.keepArchivedTab?(context.archived.id, .saved, assignment)
        coordinator.actions.openHistoryEntry(HistoryPlace(entry), assignment)
        coordinator.actions.keepHistoryEntry?(HistoryPlace(entry), .saved, assignment)
        coordinator.actions.removeHistoryEntry?(HistoryPlace(entry), assignment)
        coordinator.actions.removeHistorySite?(HistoryPlace(entry), assignment)

        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.history.entries.map(\.url), [entry.url], file: file,
            line: line)
        XCTAssertTrue(port.restoredTabs.isEmpty, file: file, line: line)
        XCTAssertTrue(port.openedURLs.isEmpty, file: file, line: line)
        let source = try XCTUnwrap(
            context.browser.spaceModel(context.source.id)
        )
        XCTAssertEqual(
            source.archive.entries.map(\.tab.id),
            [context.archived.id],
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.tabs.models.contains(where: { $0.url == context.history.url }),
            file: file,
            line: line
        )
    }

    private func makeCoordinator(
        _ context: Context,
        port: RecordedPlatformActions
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            downloadCenter: context.downloadCenter,
            spaceAccess: context.access,
            platformActions: port.platformActions
        )
    }

    private func makeContext(
        isProtected: Bool = false,
        historyURL: URL = URL(fileURLWithPath: "/crest-sidebar-history")
    ) -> Context {
        let selectedTab = TabState.Seed(
            id: UUID.fixed(1, namespace: idNamespace),
            title: "Selected",
            url: URL(string: "about:blank"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let archivedTab = TabState.Seed(
            id: UUID.fixed(2, namespace: idNamespace),
            title: "Archived",
            url: URL(string: "about:blank#archived"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let archived = ArchivedTabState.Seed(
            tab: archivedTab,
            archivedAt: Date(timeIntervalSince1970: 1_700_000_002),
            reason: .closed
        )
        let history = HistoryEntryState(
            url: historyURL,
            title: "History",
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_003),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
        let source = SpaceState.Seed(
            id: UUID.fixed(3, namespace: idNamespace),
            profileID: UUID.fixed(4, namespace: idNamespace),
            name: "Source",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [selectedTab],
            archivedTabs: [archived],
            history: [history],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open
        )
        let destination = SpaceState.Seed(
            id: UUID.fixed(5, namespace: idNamespace),
            profileID: UUID.fixed(6, namespace: idNamespace),
            name: "Destination",
            symbol: "square.grid.2x2",
            accent: .rose,
            folders: [],
            tabs: []
        )
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]))
        let downloadCenter = BrowserDownloadCenter()
        let downloadItemID = downloadCenter.begin(
            profileID: source.profileID,
            filename: "Ode.dmg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        return Context(
            browser: browser,
            downloadCenter: downloadCenter,
            downloadItemID: downloadItemID,
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            destination: destination,
            archived: archived,
            history: history
        )
    }

    private func replaceProfile(of space: SpaceState.Seed, in browser: BrowserStore) {
        browser.replaceProfileForTesting(of: space.id, with: UUID.fixed(7, namespace: idNamespace))
    }

    private func downloadItem(profileID: UUID, id: UUID) -> DownloadState {
        DownloadState.fixture(
            id: id, profileID: profileID, createdAt: Date(timeIntervalSince1970: 1_700_000_004),
            filename: "Ode.dmg", progress: 0.5, phase: .downloading)
    }

    private struct Context {
        let browser: BrowserStore
        let downloadCenter: BrowserDownloadCenter
        let downloadItemID: UUID
        let access: BrowserSpaceAccessController
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let archived: ArchivedTabState.Seed
        let history: HistoryEntryState
    }

    /// A stand-in for either shell's binding, so a guard can be tested by what
    /// it lets through rather than by what a particular shell does next.
    @MainActor
    private final class RecordedPlatformActions {
        var restoredTabs: [UUID] = []
        var openedURLs: [URL] = []
        var openedDownloads: [(item: DownloadState, destination: BrowserUtilityDownloadDestination)] = []
        var canceledDownloads: [UUID] = []
        var clearedDownloads: [UUID] = []

        var platformActions: BrowserSidebarUtilityPlatformActions {
            BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [.open, .revealInFinder],
                openHistoryEntry: { url, _ in self.openedURLs.append(url) },
                selectRestoredTab: { self.restoredTabs.append($0) },
                openFinishedDownload: { item, destination in
                    self.openedDownloads.append((item, destination))
                },
                cancelDownload: { self.canceledDownloads.append($0) },
                clearDownload: { self.clearedDownloads.append($0) }
            )
        }
    }
}
