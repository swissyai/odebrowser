import AppKit

/// A command the menu bar offers beside Ode's shortcut commands, which the
/// shell runs: the application's own, under the application's and the Help
/// menus, and the few of a page's that no shortcut names.
@MainActor
struct BrowserMacApplicationAction: Hashable {
    // MARK: - Static Variables

    static let about = BrowserMacApplicationAction(name: "about", title: "About Ode") { $0.showAbout() }
    static let updates = BrowserMacApplicationAction(
        name: "updates", title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath",
        isEnabled: { $0.canCheckForUpdates }, perform: { $0.checkForUpdates() })
    static let settings = BrowserMacApplicationAction(
        name: "settings", title: "Settings…", symbol: "gearshape", keyEquivalent: ","
    ) { $0.openSettings() }
    /// The dated copies of the session, one of which Ode restores as it quits
    /// and opens again.
    static let restoreEarlierCopy = BrowserMacApplicationAction(
        name: "restore-earlier-copy", title: "Restore from an Earlier Copy…", symbol: "clock.arrow.circlepath",
        isEnabled: { $0.canRestoreEarlierCopy }, perform: { $0.restoreEarlierCopy() })
    /// Ends every agent's connection and keeps agents out of the tabs they
    /// used until Ode quits, while any agent is connected.
    static let stopAllAgents = BrowserMacApplicationAction(
        name: "stop-all-agents", title: "Stop All Agents", symbol: "stop.circle",
        isEnabled: { $0.hasConnectedAgents }, perform: { $0.stopAllAgents() })
    static let gettingStarted = BrowserMacApplicationAction(
        name: "getting-started", title: "Getting Started with Ode"
    ) { $0.openGettingStarted() }
    static let feedback = BrowserMacApplicationAction(
        name: "feedback", title: "Share Feedback…", symbol: "bubble.left"
    ) { $0.openFeedbackSettings() }
    /// Translates the whole shown page, offered while the translation toolbar
    /// is.
    static let translatePage = BrowserMacApplicationAction(
        name: "translate-page", title: "Translate Page", symbol: "translate", offeredWith: .toggleTranslationToolbar,
        isEnabled: { $0.pageActions?.canPerform(.toggleTranslationToolbar) == true },
        perform: { $0.pageActions?.translatePage() })
    /// Shows the tab whose media plays, from a window or Space away from it.
    static let backToPlayingTab = BrowserMacApplicationAction(
        name: "back-to-playing-tab", title: "Back to Playing Tab", symbol: "arrow.uturn.backward",
        keyEquivalent: "\r", modifiers: [.command, .option],
        isEnabled: { $0.canReturnToPlayingTab }, perform: { $0.returnToPlayingTab() })
    static let all: [BrowserMacApplicationAction] = [
        about, updates, settings, restoreEarlierCopy, stopAllAgents, gettingStarted, feedback, translatePage,
        backToPlayingTab,
    ]

    // MARK: - Variables

    /// The action's name, which identifies it.
    nonisolated let name: String
    let title: LocalizedStringResource
    /// The symbol its menu item shows, or none.
    let symbol: String?
    /// The key that runs it with `modifiers`, or none.
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
    /// The shortcut command the device must offer for the menu to show the
    /// action, or nil when it always shows.
    let offeredWith: ShortcutCommand?
    private let availability: @MainActor (BrowserMacShell) -> Bool
    private let run: @MainActor (BrowserMacShell) -> Void

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String? = nil, keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command, offeredWith: ShortcutCommand? = nil,
        isEnabled: @escaping @MainActor (BrowserMacShell) -> Bool = { _ in true },
        perform: @escaping @MainActor (BrowserMacShell) -> Void
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.offeredWith = offeredWith
        availability = isEnabled
        run = perform
    }

    // MARK: - Actions - Running

    /// Whether the menu shows the action, as the read model `state` says.
    func isOffered(in state: CoreState) -> Bool {
        offeredWith?.isOffered(in: state) ?? true
    }

    /// Whether `shell` can run the action now.
    func isEnabled(in shell: BrowserMacShell) -> Bool {
        availability(shell)
    }

    /// Runs the action in `shell`.
    func perform(in shell: BrowserMacShell) {
        run(shell)
    }

    /// Runs the action named `name` as its menu item does, when the menu bar
    /// offers it enabled now, answering whether it ran.
    static func runFromMenu(_ name: String) -> Bool {
        guard let menu = NSApp.mainMenu, let (owner, index) = menuItem(named: name, in: menu) else { return false }
        owner.update()
        guard owner.items[index].isEnabled, !owner.items[index].isHidden else { return false }
        owner.performActionForItem(at: index)
        return true
    }

    /// The menu holding the item that runs the action named `name`, and its
    /// index there, searching `menu` and its submenus.
    private static func menuItem(named name: String, in menu: NSMenu) -> (NSMenu, Int)? {
        for (index, item) in menu.items.enumerated() {
            if (item.representedObject as? BrowserMacApplicationAction)?.name == name { return (menu, index) }
            if let submenu = item.submenu, let found = menuItem(named: name, in: submenu) { return found }
        }
        return nil
    }
}

// MARK: - Hashable

extension BrowserMacApplicationAction {
    nonisolated static func == (lhs: BrowserMacApplicationAction, rhs: BrowserMacApplicationAction) -> Bool {
        lhs.name == rhs.name
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
