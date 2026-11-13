import Foundation
import Observation

/// Finds icons for the tabs of the session the core keeps in its file that
/// wear none: tabs an import brought, or that an earlier release kept without
/// one, which no page has loaded since. Pinned tabs go first, then saved tabs,
/// then the rest. Each icon found is worn and kept like one a page reported,
/// so it is there at the next launch. It waits for the launch to settle and
/// for each change to the session to pause, runs a few lookups at a time at
/// low priority, never looks inside a locked Space, and leaves alone a tab
/// whose page or the person chose its icon since.
///
/// Only the kept session has one, so private windows never reach the network
/// for an icon this way.
@MainActor
final class BrowserTabIconBackfill {
    // MARK: - Static Variables

    static let launchDelay: Duration = .seconds(3)
    private static let settleDelay: Duration = .seconds(2)
    /// How long a tab asked about and given nothing waits before it is asked
    /// again, beyond the finder's own retry times.
    private static let askAgainDelay: Duration = .seconds(15 * 60)
    /// Placements in the order their tabs are filled.
    private static let placementOrder: [TabPlacement] = [.pinned, .saved, .current]

    // MARK: - Types

    /// A tab that wears no icon, at the address and in the profile it was
    /// asked about.
    private struct Want: Hashable, Sendable {
        let tabID: UUID
        let address: URL
        let profileID: UUID
    }

    // MARK: - Variables

    private let state: CoreState
    private let workspaceID: UUID
    private let find: @Sendable (URL, UUID) async -> Data?
    /// How many tabs are looked up at once; work is handed out in order.
    private let concurrentLookups: Int
    private var run: Task<Void, Never>?
    private var isStarted = false
    private var needsAnotherPass = false
    /// When each tab was last asked about, at the address it had then.
    private var asked: [UUID: (address: URL, at: ContinuousClock.Instant)] = [:]

    // MARK: - Initializers

    /// Fills the tabs of the workspace `workspaceID` that `state` holds with
    /// the icons `find` answers for a page in a profile, `concurrentLookups`
    /// at a time.
    init(
        state: CoreState, workspaceID: UUID, concurrentLookups: Int = BrowserSiteIconFinder.maximumConcurrentLookups,
        find: @escaping @Sendable (URL, UUID) async -> Data? = { pageURL, profileID in
            await BrowserSiteIconFinder.shared.icon(for: pageURL, profileID: profileID)?.data
        }
    ) {
        precondition(concurrentLookups > 0, "The backfill looks up at least one tab at a time.")
        self.state = state
        self.workspaceID = workspaceID
        self.concurrentLookups = concurrentLookups
        self.find = find
    }

    isolated deinit { run?.cancel() }

    /// The backfill of a launch whose windows show `browser`: one for the
    /// session the core keeps in its file, none in a test, a preview or a
    /// private window.
    static func forLaunch(_ browser: BrowserStore, environment: BrowserLaunchEnvironment) -> BrowserTabIconBackfill? {
        guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime, !browser.isPrivateBrowsing,
            browser.family.keepsWindowRecords
        else { return nil }
        return BrowserTabIconBackfill(state: browser.core.state, workspaceID: browser.family.workspaceID)
    }

    // MARK: - Actions - Filling

    /// Starts filling once the launch settles, `delay` from now, and again
    /// whenever the tabs, their icons or which Spaces are unlocked change.
    func start(after delay: Duration = launchDelay) {
        guard !isStarted else { return }
        isStarted = true
        schedule(after: delay)
    }

    private func schedule(after delay: Duration) {
        guard run == nil else {
            needsAnotherPass = true
            return
        }
        run = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.fill()
        }
    }

    private func fill() async {
        repeat {
            needsAnotherPass = false
            let wanted = withObservationTracking(
                { self.wanted() },
                onChange: { [weak self] in
                    Task { @MainActor in self?.schedule(after: Self.settleDelay) }
                })
            await fetch(wanted)
        } while needsAnotherPass && !Task.isCancelled
        run = nil
    }

    /// Asks for each of `wanted` a few at a time, and dresses each tab that
    /// still wants its icon when the answer comes.
    private func fetch(_ wanted: [Want]) async {
        let find = find
        let now = ContinuousClock.now
        for want in wanted { asked[want.tabID] = (want.address, now) }
        await withTaskGroup(of: (Want, Data?).self) { group in
            var pending = wanted.makeIterator()
            for _ in 0..<concurrentLookups {
                guard let want = pending.next() else { break }
                group.addTask(priority: .utility) { (want, await find(want.address, want.profileID)) }
            }
            while let (want, data) = await group.next() {
                if let data {
                    state.adoptFoundImage(data, for: want.tabID, at: want.address, in: workspaceID)
                }
                if let next = pending.next(), !Task.isCancelled {
                    group.addTask(priority: .utility) { (next, await find(next.address, next.profileID)) }
                }
            }
        }
    }

    /// The tabs of unlocked Spaces that wear no icon and could wear one a
    /// site serves, pinned first, that were not asked about lately.
    private func wanted() -> [Want] {
        guard let workspace = state.workspaces[workspaceID] else { return [] }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        let now = ContinuousClock.now
        var wanted: [(order: Int, index: Int, want: Want)] = []
        for space in workspace.spaces.models where !deleting.contains(space.id) && !isLocked(space) {
            for tab in space.tabs.models {
                guard let order = Self.placementOrder.firstIndex(of: tab.placement), tab.iconMode.showsFavicon,
                    tab.nativeContent == nil, tab.isWebPage, let address = tab.address,
                    ["http", "https"].contains(address.scheme?.lowercased()), !address.isLocalDevelopmentAddress,
                    state.favicons.icon(of: tab.id) == nil
                else { continue }
                if let last = asked[tab.id], last.address == address, now - last.at < Self.askAgainDelay {
                    continue
                }
                let want = Want(tabID: tab.id, address: address, profileID: space.profileID)
                wanted.append((order, wanted.count, want))
            }
        }
        return wanted.sorted { ($0.order, $0.index) < ($1.order, $1.index) }.map(\.want)
    }

    /// Whether `space` shows only once unlocked and is not unlocked now.
    private func isLocked(_ space: SpaceModel) -> Bool {
        space.settings.requiresAuthentication
            && state.spaceAccess[BrowserSpaceRuntimeAssignment(space: space)]?.isUnlocked != true
    }
}
