import SwiftUI

/// One Space's settings: its icon and name over a tab bar of its pages.
struct BrowserSettingsSpacePage: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Bindable var tabState: BrowserSettingsTabState
    let openSpace: BrowserSettingsOpenSpaceAction
    let addSubSpace: (UUID) -> Void

    @State private var downloads = BrowserSpaceDownloadSettingsModel()
    @State private var passwordSearchText = ""
    @State private var pendingDeletion: BrowserSpaceDeletionRequest?
    @State private var pendingGroupChange: BrowserSpaceGroupChange?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !browser.isPrivateBrowsing {
                BrowserSpaceGroupEmblemRow(
                    browser: browser, space: space, draggedSpaceID: $tabState.draggedSpaceID,
                    select: { openSpace($0) }, addSubSpace: addSubSpace,
                    requestGroupChange: { pendingGroupChange = $0 }, requestDeletion: { pendingDeletion = $0 }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            Divider()

            if spaceAccess.isLocked(space) {
                BrowserSettingsPane(.spaces) {
                    BrowserSettingsPrivateSpaceAccessSection(
                        space: space,
                        accessController: spaceAccess,
                        detail: "Unlock this Space to see its settings."
                    )
                }
            } else {
                tabPicker
                tabContent
                    .environment(\.browserSettingsScrollKey, "space-\(space.id)-\(tab.name)")
                    .id(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BrowserSettingsCanvas.background)
        .browserSpaceDeletionConfirmation(
            $pendingDeletion, browser: browser, spaceAccess: spaceAccess, dataDeleter: dataDeleter
        )
        .browserSpaceGroupChangeConfirmation($pendingGroupChange, browser: browser, spaceAccess: spaceAccess)
    }

    /// The color preset standing for the house this Space started from, on
    /// the Space's own look, or else the scheme it started from.
    private var startingAppearance: SpaceBranding? {
        if let house = SpaceHouse.startingPoint(of: space.settings.look) {
            var look = space.settings.look
            look.colors = ColorPalette(colors: [house.preset.swatch])
            look.iconStyle = .simpleSymbol
            return look
        }
        return SpaceScheme.startingPoint(of: space.settings.look)?.applying(to: space.settings.look)
    }

    private func resetAppearance() {
        guard let startingAppearance else { return }
        browser.spaceBrandingBinding(in: space).wrappedValue = startingAppearance
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrowserSpaceIcon(space: space, form: .tile, size: 26)
            BrowserInlineSpaceName(
                name: browser.spaceNameBinding(in: space),
                size: 18,
                titleFont: .title3.weight(.semibold),
                requestsEditing: renameRequest
            )
            .disabled(spaceAccess.isLocked(space))
            Menu {
                Group {
                    BrowserSettingsSpaceMenu(
                        browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace,
                        addSubSpace: addSubSpace, requestDeletion: { pendingDeletion = $0 },
                        requestGroupChange: { pendingGroupChange = $0 })
                    Divider()
                    Button("Reset Appearance", systemImage: "arrow.counterclockwise") { resetAppearance() }
                        .disabled(startingAppearance == nil || startingAppearance == space.settings.look)
                }
                .odeMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Space actions")
            .accessibilityLabel("Space actions")
            .accessibilityIdentifier("space-settings-menu")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-page-header")
    }

    private var renameRequest: Binding<Bool> {
        Binding {
            tabState.renameSpaceID == space.id
        } set: { requested in
            if !requested, tabState.renameSpaceID == space.id { tabState.renameSpaceID = nil }
        }
    }

    // MARK: - Tabs

    private var tabs: [BrowserSpaceSettingsTab] {
        BrowserSpaceSettingsTab.provided(in: browser.core.state)
    }

    /// The tab shown: the one last chosen, while this device offers it.
    private var tab: BrowserSpaceSettingsTab {
        tabs.contains(tabState.spaceTab) ? tabState.spaceTab : .appearance
    }

    private var tabPicker: some View {
        Picker("Page", selection: Binding(get: { tab }, set: { tabState.spaceTab = $0 })) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("space-settings-tabs")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab.kind {
        case .appearance:
            BrowserSpaceEditorView(browser: browser, space: space)
        case .browsing:
            browsingPane
        case .privacy:
            BrowserPrivacySettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                permissionCenter: pages.permissionCenter,
                fixedSpaceID: space.id
            )
        case .passwords:
            BrowserPasswordSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: .macOSSpacePage,
                searchText: $passwordSearchText,
                fixedSpaceID: space.id
            )
        case .extensions:
            BrowserEngineExtensionSettingsPane(browser: browser, spaceAccess: spaceAccess, spaceID: space.id)
        }
    }

    /// The Space's browsing, downloads and deletion, with its download
    /// settings read fresh whenever the Space changes.
    private var browsingPane: some View {
        BrowserSettingsPane(.spaces) {
            BrowserSpaceBrowsingSection(browser: browser, space: space)
            BrowserSpaceGroupPinnedTabsSection(browser: browser, space: space)
            BrowserSpaceDownloadsSection(settings: downloads.settings(for: space))
            BrowserSpaceDeletionSection(browser: browser, spaceID: space.id, dataDeleter: dataDeleter)
        }
        .task(id: space.id) { downloads.refresh(for: space.id) }
    }
}

/// What can be done to a Space from its sidebar row or its page, including
/// moving it into or out of a group, each after a confirmation.
struct BrowserSettingsSpaceMenu: View {
    let browser: BrowserStore
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let openSpace: BrowserSettingsOpenSpaceAction
    let addSubSpace: (UUID) -> Void
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void

    var body: some View {
        let order = BrowserSpaceOrderActions(browser: browser, spaceID: space.id)
        Button("Rename", systemImage: "pencil") { openSpace(space.id, intent: .rename) }
        Button("Edit Appearance…", systemImage: "paintpalette") { openSpace(space.id, tab: .appearance) }
        Divider()
        Button("Move Up", systemImage: "arrow.up", action: order.moveUp).disabled(!order.canMoveUp)
        Button("Move Down", systemImage: "arrow.down", action: order.moveDown).disabled(!order.canMoveDown)
        Divider()
        BrowserSpaceGroupMenuItems(
            browser: browser, space: space, requestGroupChange: requestGroupChange, addSubSpace: addSubSpace)
        Divider()
        Toggle("Lock Space", systemImage: "lock", isOn: lock)
        Divider()
        BrowserSpaceDeletionMenuItems(browser: browser, space: space, requestDeletion: requestDeletion)
    }

    private var lock: Binding<Bool> {
        Binding {
            space.settings.requiresAuthentication
        } set: { isRequired in
            Task {
                await spaceAccess.updatePolicy(
                    isRequired ? .deviceOwnerAuthentication : .open,
                    matching: BrowserSpaceRuntimeAssignment(space: space),
                    in: browser
                )
            }
        }
    }
}
