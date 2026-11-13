import AppKit
import Foundation
import Observation

/// One disposable browser, not a learning record. It has its own core, profiles,
/// credentials and window selection. Dropping it cannot remove a real tab.
@Observable
@MainActor
final class BrowserOnboardingPractice {
    // MARK: - Variables

    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome = BrowserChromeState(utilityPresentation: BrowserUtilityPresentationState(defaults: nil))
    let transientBrowsing = BrowserTransientBrowsingCoordinator()
    let shortcuts: BrowserShortcutStore
    let homeID: UUID
    let awayID: UUID
    let sampleID: UUID
    private(set) var foundSample = false
    private(set) var visitedOtherSpace = false
    private(set) var returnedHome = false

    var actions: BrowserCommandActions {
        BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
    }

    var canFindSample: Bool {
        browser.selectedSpaceID == homeID && browser.selectedTabID(in: homeID) == sampleID
    }

    // MARK: - Initializers

    init(shortcuts: BrowserShortcutStore) throws {
        guard let document = Bundle.main.url(forResource: "OnboardingPractice", withExtension: "html"),
            let trailURL = URL(string: "#trail", relativeTo: document)?.absoluteURL,
            let packingURL = URL(string: "#packing", relativeTo: document)?.absoluteURL
        else { throw CocoaError(.fileNoSuchFile) }
        self.shortcuts = shortcuts
        homeID = UUID()
        awayID = UUID()
        sampleID = UUID()
        let otherTabID = UUID()
        let core = OdeCore()
        core.engines.register(
            WebKitEngineBinding(
                keepsProfilesInMemory: true,
                contentRuleLists: BrowserContentRuleListProvider(core: core, ruleListStore: nil)),
            isDefault: true)
        let seed = SessionState.Seed(spaces: [
            SpaceState.Seed(
                id: homeID, name: String(localized: "Weekend"), symbol: "mountain.2", accent: .indigo,
                tabs: [
                    TabState.Seed(
                        id: sampleID, title: String(localized: "Trail notes"), url: trailURL, placement: .current,
                        customTitle: String(localized: "Trail notes")),
                    TabState.Seed(
                        id: otherTabID, title: String(localized: "Packing list"), url: packingURL, placement: .current,
                        customTitle: String(localized: "Packing list")),
                ]),
            SpaceState.Seed(
                id: awayID, name: String(localized: "Work"), symbol: "briefcase", accent: .orange,
                tabs: [TabState.Seed(title: String(localized: "Packing list"), url: packingURL, placement: .current)]),
        ])
        browser = BrowserStore(
            credentialVault: InMemoryCredentialVault(), browsingMode: .standard,
            family: BrowserStoreFamily(seed: seed, core: core, workspaceKind: .practice), core: core)
        pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        browser.selectSpace(homeID)
        browser.selectTab(otherTabID)
    }

    // MARK: - Actions - Practice

    /// Observe effects in this workspace, never the keys that requested them.
    func observe() {
        if canFindSample { foundSample = true }
        if browser.selectedSpaceID == awayID { visitedOtherSpace = true }
        if visitedOtherSpace, browser.selectedSpaceID == homeID,
            browser.spaceModel(homeID)?.tabs.model(sampleID) != nil
        {
            returnedHome = true
        }
    }

    func shortcutLabel(_ command: ShortcutCommand) -> String {
        shortcuts.shortcut(for: command)?.displayString ?? String(localized: "No shortcut assigned")
    }

    /// Uses the configured production resolver and the same actions as menus.
    /// Other shortcuts stay with their native control; no window command can
    /// close the setup window from this disposable workspace.
    func handle(_ event: NSEvent) -> Bool {
        guard
            let command = shortcuts.command(
                for: event,
                isEnabled: { command in
                    [.newTab, .previousSpace, .nextSpace].contains(command) && self.actions.canPerform(command)
                })
        else { return false }
        actions.perform(command)
        return true
    }

    func leave() {
        chrome.dismissCommandPalette()
        pages.closeWindowWorkspace()
        browser.family.close()
    }
}
