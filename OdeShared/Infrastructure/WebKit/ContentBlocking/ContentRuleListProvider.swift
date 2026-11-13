import Foundation
import WebKit

/// Compiles the core's content rule lists into a WebKit rule-list store and
/// hands out the compiled lists. A list the store already holds under its
/// identifier is never compiled again, so a launch compiles only what changed,
/// and the lists Ode compiled that no set names any more are removed. The
/// set before the current one stays compiled for the rest of the launch: the
/// store compiles on the main thread, parsing a whole set first, and a switch
/// back, as between Balanced and Strict, then only looks its lists up.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    // MARK: - Static Variables

    /// The identifiers of the lists Ode compiles, current and past, which
    /// tell its own lists apart from another client's in a shared store.
    private static let ownedPrefixes = ["com.odebrowser.ode.content-filter.", "com.odebrowser.ode.content-blocking."]
    /// How an isolated launch names its store in the temporary folder, its
    /// process identifier following.
    nonisolated private static let isolatedStorePrefix = "OdeIsolatedContentRules-"
    /// This process's isolated store, which goes when the process exits.
    nonisolated(unsafe) private static var isolatedStore: URL?

    // MARK: - Types

    private enum Failure: Error {
        case coreUnavailable
    }

    // MARK: - Variables

    /// The core owns this provider through its engine binding. Rule requests
    /// borrow it and never keep it alive after it closes.
    private weak var core: OdeCore?
    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cached: (set: ContentRuleListSet, lists: [WKContentRuleList])?
    /// The set compiled before the cached one this launch, whose lists stay
    /// in the store.
    private var previous: ContentRuleListSet?

    // MARK: - Initializers

    init(
        core: OdeCore,
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter()
    ) {
        self.core = core
        self.ruleListStore = ruleListStore
        self.compiler = compiler
    }

    /// The provider a launch uses: an isolated launch compiles into a store of
    /// its own under the temporary folder, which no other launch reads and
    /// which goes when the launch ends.
    static func forLaunch(
        core: OdeCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        guard launchEnvironment.requiresIsolation else { return BrowserContentRuleListProvider(core: core) }
        let folder = isolatedStore ?? makeIsolatedStore()
        return BrowserContentRuleListProvider(core: core, ruleListStore: WKContentRuleListStore(url: folder))
    }

    // MARK: - Actions - Compiling

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        guard let ruleListStore else { return [] }
        guard let core else { throw Failure.coreUnavailable }
        let set: ContentRuleListSet
        if let published = core.state.contentRuleLists {
            set = published
        } else {
            // The core starts converting on the first ask and announces the
            // rules once they are ready; until then it answers what it has.
            guard let answered = try? core.query(ContentRuleLists()) else { return [] }
            if core.state.contentRuleLists == nil { core.state.contentRuleLists = answered }
            set = core.state.contentRuleLists ?? answered
        }
        if let cached, cached.set == set { return cached.lists }

        let lists = try await compiler.compile(
            identifiers: set.identifiers,
            source: { [weak core] identifier in
                guard let core else { throw Failure.coreUnavailable }
                return try core.query(ContentRuleListSource(identifier: identifier)).source
            },
            store: ruleListStore
        )
        previous = cached?.set
        cached = (set, lists)
        await removeStaleLists(keeping: Set(set.identifiers + (previous?.identifiers ?? [])), from: ruleListStore)
        return lists
    }

    /// Removes the lists Ode compiled earlier that `current` no longer names.
    private func removeStaleLists(keeping current: Set<String>, from store: WKContentRuleListStore) async {
        for identifier in await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
        where !current.contains(identifier) && Self.ownedPrefixes.contains(where: identifier.hasPrefix) {
            await BrowserContentRuleListCompiler.remove(identifier: identifier, store: store)
        }
    }

    // MARK: - Actions - Isolated Stores

    /// Makes this launch's store and removes it as the process exits. The
    /// stores of isolated launches that ended without removing theirs, such as
    /// one that was killed, go too.
    private static func makeIsolatedStore() -> URL {
        let temporary = FileManager.default.temporaryDirectory
        let folder = temporary.appendingPathComponent("\(isolatedStorePrefix)\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        isolatedStore = folder
        atexit {
            guard let store = BrowserContentRuleListProvider.isolatedStore else { return }
            try? FileManager.default.removeItem(at: store)
        }
        Task.detached(priority: .utility) { removeEndedIsolatedStores(in: temporary) }
        return folder
    }

    /// Removes each isolated store whose process no longer runs. A store whose
    /// process runs, or may run under a reused identifier, stays.
    nonisolated private static func removeEndedIsolatedStores(in temporary: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix(isolatedStorePrefix) {
            guard let process = pid_t(name.dropFirst(isolatedStorePrefix.count)), process != getpid() else { continue }
            // Signal 0 asks whether the process exists without reaching it.
            guard kill(process, 0) == -1, errno == ESRCH else { continue }
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(name, isDirectory: true))
        }
    }
}
