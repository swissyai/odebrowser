import SwiftUI

/// The content seam used by both single cards and Split View, on every shell.
/// The surrounding layout owns identity, geometry, focus, and placement.
struct BrowserNativeTabHost: View {
    let tab: TabStateModel
    let space: SpaceModel
    /// The shell's floating controls remain outside native scrolling content.
    var bottomChromeHeight: CGFloat = 0
    @Environment(\.browserSettingsTabContent) private var settingsContent
    @Environment(\.browserNativeTabActions) private var actions
    @Environment(\.browserNativeTabs) private var nativeTabs

    var body: some View {
        Group {
            if let content = tab.nativeTabContent,
                let runtime = nativeTabs?.runtime(matching: assignment, content: content)
            {
                switch tab.nativeView {
                case .gettingStarted?:
                    BrowserGettingStartedTabAdapter(runtime: runtime, bottomChromeHeight: bottomChromeHeight) { url in
                        actions.openURL(assignment, content, url)
                    }
                case .settings?:
                    if let settingsContent {
                        settingsContent.makeView(runtime)
                    } else {
                        ContentUnavailableView("Settings unavailable", systemImage: "gearshape")
                    }
                default:
                    ContentUnavailableView(
                        "This tab needs a newer Ode", systemImage: "square.stack.3d.up",
                        description: Text("Its content is still saved. Update Ode to open it.")
                    )
                }
            }
        }
        .id(tab.nativeTabContent.flatMap { nativeTabs?.runtime(matching: assignment, content: $0)?.id })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaPadding(.bottom, bottomChromeHeight)
    }

    private var assignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
    }
}

/// Native views can ask the shell to open a website, but cannot borrow a page
/// pool, switch profiles, or navigate whichever tab happens to be focused later.
struct BrowserNativeTabActions {
    var openURL: @MainActor (BrowserTabRuntimeAssignment, BrowserNativeTabContent, URL) -> Void = { _, _, _ in }
    var dismiss: @MainActor (BrowserTabRuntimeAssignment, BrowserNativeTabContent) -> Void = { _, _ in }
    var guideContext: @MainActor (BrowserTabRuntimeAssignment) -> BrowserGettingStartedGuideContext? = { _ in nil }
    var openSearchSettings: @MainActor (BrowserTabRuntimeAssignment) -> Bool = { _ in false }
    /// Runs one of the window's commands, as a guide's "Show me" does,
    /// answering whether the window offers it.
    var runCommand: @MainActor (ShortcutCommand) -> Bool = { _ in false }

    @MainActor
    init(
        browser: BrowserStore, spaceAccess: BrowserSpaceAccessController,
        commands: BrowserCommandPaletteCommandRegistry? = nil, didOpenURL: @escaping @MainActor () -> Void
    ) {
        let ownsGuide: @MainActor (BrowserTabRuntimeAssignment) -> Bool = { source in
            let assignment = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
            guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
            else { return false }
            return !browser.isPrivateBrowsing && browser.selectedTabID(in: space.id) == source.tabID
                && space.shownTab(source.tabID)?.nativeTabContent == .gettingStarted
        }
        guideContext = { source in
            ownsGuide(source) ? BrowserGettingStartedGuideContext(browser: browser) : nil
        }
        openSearchSettings = { source in
            guard ownsGuide(source), let commands else { return false }
            return commands.openSettings(BrowserSettingsDestination.search.name).wasPerformed
        }
        runCommand = { command in
            guard let commands else { return false }
            return commands.perform(command).wasPerformed
        }
        dismiss = { source, content in
            let assignment = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
            guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess),
                browser.selectedTabID(in: space.id) == source.tabID,
                space.shownTab(source.tabID)?.nativeTabContent == content
            else { return }
            browser.dismissNativeTab(source.tabID, matching: assignment)
            didOpenURL()
        }
        openURL = { source, content, url in
            guard
                let space = browser.selectedUnlockedSpace(
                    matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                    accessController: spaceAccess),
                space.shownTab(source.tabID)?.nativeTabContent == content,
                ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            else { return }
            browser.openNewTab(url: url, in: space.id)
            didOpenURL()
        }
    }

    init() {}
}

private struct BrowserNativeTabActionsKey: EnvironmentKey {
    static let defaultValue = BrowserNativeTabActions()
}

extension EnvironmentValues {
    var browserNativeTabActions: BrowserNativeTabActions {
        get { self[BrowserNativeTabActionsKey.self] }
        set { self[BrowserNativeTabActionsKey.self] = newValue }
    }
}
