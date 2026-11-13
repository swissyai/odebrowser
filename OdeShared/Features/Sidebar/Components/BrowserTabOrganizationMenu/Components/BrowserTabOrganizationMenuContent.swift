import SwiftUI

struct BrowserTabOrganizationMenuContent: View {
    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    var isLoaded = true
    var renameTab: (() -> Void)? = nil
    var changeIcon: (() -> Void)? = nil

    @Environment(\.layoutDirection) private var layoutDirection

    init(menu: BrowserTabOrganizationMenu) {
        tab = menu.tab
        context = menu.context
        assignment = menu.assignment
        isLoaded = menu.isLoaded
        renameTab = menu.renameTab
        changeIcon = menu.changeIcon
    }

    private var browser: BrowserStore { context.browser }
    private var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }

    var body: some View {
        sharingItems
        linkItem
        renameItem
        editItems
        pinItem
        currentFolderItems
        saveInFolderMenu
        moveItems

        Divider()

        splitItems

        Divider()

        loadingItems
        closingItems
    }

    /// Stop Sharing, while the tab takes part in tab sharing.
    @ViewBuilder
    private var sharingItems: some View {
        if context.takesPartInTabSharing(tab.id) {
            Button {
                performIfCurrent { context.stopTabSharing(tab.id) }
            } label: {
                Label {
                    Text("Stop Sharing", comment: "Stops the tab sharing a tab takes part in.")
                } icon: {
                    Image(systemName: "rectangle.slash")
                }
            }

            Divider()
        }
    }

    /// Copy Link URL, for a web page.
    @ViewBuilder
    private var linkItem: some View {
        if tab.isWebPage {
            Button("Copy Link URL", systemImage: "link") {
                organizationAction.copyLinkURL(for: assignment)
            }
            .disabled(!context.isCurrent(sourceAssignment))

            Divider()
        }
    }

    /// Rename Tab, where the row can rename it.
    @ViewBuilder
    private var renameItem: some View {
        if let renameTab {
            Button("Rename Tab…", systemImage: "pencil") {
                performIfCurrent { renameTab() }
            }

            Divider()
        }
    }

    /// The tab's title, icon and saved location edits.
    @ViewBuilder
    private var editItems: some View {
        if !tab.isStartPage {
            BrowserTabEditActions(
                tab: tab,
                favicons: context.favicons,
                isLoaded: isLoaded,
                pullNewIcon: { context.pullNewIcon(tab.id) },
                restoreSavedLocation: context.restoreSavedLocation.map { restore in { restore(tab.id) } },
                performIfCurrent: performIfCurrent,
                replaceSavedLocation: {
                    browser.replaceTabSavedLocationWithCurrent(
                        tab.id,
                        in: assignment.spaceID
                    )
                },
                clearIcon: {
                    browser.clearTabIcon(
                        for: tab.id,
                        matching: sourceAssignment
                    )
                },
                changeIcon: { changeIcon?() },
                tidyTitle: { browser.tidyTabTitle(tab.id, matching: sourceAssignment) },
                restoreOriginalTitle: {
                    browser.setTabCustomTitle(
                        nil,
                        for: tab.id,
                        matching: sourceAssignment
                    )
                }
            )

            Divider()
        }
    }

    @ViewBuilder
    private var pinItem: some View {
        // Unpin Tab takes Pin Tab's place so the two read as a pair; it moves
        // the tab to Current Tabs, as ⌘D's Pin or Unpin Tab does.
        if tab.placement == .pinned {
            Button("Unpin Tab", systemImage: "pin.slash") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .current
                    )
                }
            }
        } else {
            Button("Pin Tab", systemImage: "pin") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .pinned
                    )
                }
            }
        }
    }

    /// Filing an open tab into, or out of, a Current Tabs folder, and nesting it.
    @ViewBuilder
    private var currentFolderItems: some View {
        if !tab.placement.isDurable, !tab.isStartPage {
            Menu("Add to Current Tabs Folder", systemImage: "folder.badge.plus") {
                Group {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        performIfCurrent {
                            browser.createTabFolder([tab.id], in: assignment.spaceID)
                        }
                    }
                    let folders = context.space.folderChoices(in: [.current]).map(\.folder)
                    if !folders.isEmpty { Divider() }
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            performIfCurrent {
                                browser.fileTabs(
                                    [tab.id], matching: sourceAssignment, into: folder.id, location: .current)
                            }
                        } label: {
                            Label {
                                Text(verbatim: folder.shownTitle)
                            } icon: {
                                BrowserFolderMenuIcon(systemName: "folder.fill", color: folder.displayColor)
                            }
                        }
                        .disabled(folder.id == tab.folderID)
                    }
                }
                .odeMenuActionLabelStyle()
            }
            if tab.folderID != nil {
                Button("Remove from Folder", systemImage: "folder.badge.minus") {
                    performIfCurrent {
                        browser.fileTabs([tab.id], matching: sourceAssignment, into: nil, location: .current)
                    }
                }
            }
            nestingItems
        }
    }

    @ViewBuilder
    private var saveInFolderMenu: some View {
        Menu("Save in Folder", systemImage: "folder") {
            Group {
                Button("Saved Tabs", systemImage: "bookmark") {
                    performIfCurrent {
                        browser.moveTab(
                            tab.id,
                            matching: sourceAssignment,
                            to: .saved
                        )
                    }
                }
                .disabled(tab.placement == .saved && tab.folderID == nil)

                let savedFolders = context.space.folderChoices(in: [.saved])
                if !savedFolders.isEmpty {
                    Divider()
                    ForEach(savedFolders) { choice in
                        Button {
                            performIfCurrent {
                                browser.moveTab(
                                    tab.id,
                                    matching: sourceAssignment,
                                    to: .saved,
                                    folderID: choice.id
                                )
                            }
                        } label: {
                            Label {
                                Text(choice.pathTitle)
                            } icon: {
                                BrowserFolderArtwork(
                                    symbol: choice.folder.displaySymbol, color: choice.folder.displayColor)
                            }
                        }
                        .disabled(
                            tab.placement == .saved && tab.folderID == choice.id
                        )
                    }
                }
            }
            .odeMenuActionLabelStyle()
        }
    }

    /// Moving the tab back to Current Tabs or into another Space.
    @ViewBuilder
    private var moveItems: some View {
        if tab.placement.isDurable, tab.placement != .pinned {
            Button("Move to Current Tabs", systemImage: "rectangle.stack") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .current
                    )
                }
            }
        }

        let otherSpaces = availableDestinationSpaces
        if !otherSpaces.isEmpty {
            Menu("Move to Space", systemImage: "square.grid.2x2") {
                ForEach(Array(browser.grouped(otherSpaces).enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { space in
                        moveButton(to: space)
                    }
                }
                .odeMenuActionLabelStyle()
            }
            .tint(.primary)
        }
    }

    /// Splitting the tab with the current one, and moving it along or out of its split.
    @ViewBuilder
    private var splitItems: some View {
        Button("Split with Current Tab", systemImage: "rectangle.split.2x1") {
            performIfCurrent {
                browser.splitTabWithSelectedTab(
                    tab.id,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(
            !browser.canSplitTabWithSelectedTab(
                assignment.tabID,
                matching: sourceAssignment
            )
        )

        if isRenderableSplitMember {
            moveButton(.left, title: "Move Left", systemImage: "arrow.left")
            moveButton(.right, title: "Move Right", systemImage: "arrow.right")

            Button("Remove from Split", systemImage: "rectangle.badge.minus") {
                performIfCurrent {
                    browser.removeTabFromSplit(
                        tab.id,
                        matching: sourceAssignment
                    )
                }
            }
        }
    }

    /// Keeping the page loaded, and unloading it.
    @ViewBuilder
    private var loadingItems: some View {
        if tab.nativeContent == nil {
            Button(
                tab.keepsPageLoaded ? "Stop Keeping Loaded" : "Keep Loaded",
                systemImage: tab.keepsPageLoaded ? "lock.open" : "lock"
            ) {
                performIfCurrent {
                    browser.setTabKeepsPageLoaded(
                        !tab.keepsPageLoaded,
                        for: tab.id,
                        matching: sourceAssignment
                    )
                }
            }

        }

        if isLoaded, tab.nativeContent == nil || tab.placement.isDurable {
            Button(
                !tab.placement.isDurable ? "Unload Tab" : "Close Tab",
                systemImage: !tab.placement.isDurable ? "minus" : "xmark"
            ) {
                performIfCurrent {
                    context.unload(tab.id)
                }
            }
        }
    }

    @ViewBuilder
    private var closingItems: some View {
        Button("Duplicate Tab", systemImage: "plus.square.on.square") {
            performIfCurrent {
                browser.duplicateTab(
                    tab.id,
                    matching: sourceAssignment
                )
            }
        }

        Button(
            !tab.placement.isDurable ? "Close Tab" : "Delete Tab",
            systemImage: !tab.placement.isDurable ? "xmark" : "trash",
            role: .destructive
        ) {
            let placement = tab.placement
            performIfCurrent {
                if !placement.isDurable {
                    organizationAction.close(assignment, expectedPlacement: placement)
                } else {
                    organizationAction.delete(assignment, expectedPlacement: placement)
                }
            }
        }
    }

    /// One "Move Left"/"Move Right" item, dimmed once the card is at that end.
    ///
    /// The card at the end of the run keeps the item rather than losing it: a
    /// pair of reordering items that appear and disappear as the card travels
    /// would make the menu jump under the pointer. "Remove from Split" is
    /// absent-or-present because it answers a different question — whether this
    /// row is in a split at all.
    private func moveButton(
        _ direction: BrowserSplitCardMoveDirection,
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        let offset = direction.memberOffset(layoutDirection: layoutDirection)
        return Button(title, systemImage: systemImage) {
            performIfCurrent {
                browser.moveSplitMember(
                    tab.id,
                    by: offset,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(!canStepSplitMember(by: offset))
    }

    /// Nesting the open tab under the tab above it or moving it out a level,
    /// and hiding or showing the tabs nested under it. Nesting is offered while
    /// tabs nest, and the rest wherever a tree already holds the tab.
    @ViewBuilder
    private var nestingItems: some View {
        let nests = tab.folderID == nil && tab.splitGroupID == nil
        let holdsNested = nests && browser.holdsNestedTabs(tab.id, in: context.space)
        if nests, browser.nestsTabs || tab.parentTabID != nil || holdsNested {
            Divider()
            Button("Nest Under Tab Above", systemImage: "arrow.right.to.line") {
                performIfCurrent { browser.indentTab(tab.id, matching: sourceAssignment) }
            }
            if tab.parentTabID != nil {
                Button("Move Out a Level", systemImage: "arrow.left.to.line") {
                    performIfCurrent { browser.outdentTab(tab.id, matching: sourceAssignment) }
                }
            }
            if holdsNested {
                let collapsed = tab.collapsesNestedTabs
                Button(
                    collapsed ? "Show Nested Tabs" : "Hide Nested Tabs",
                    systemImage: collapsed ? "chevron.down" : "chevron.right"
                ) {
                    performIfCurrent {
                        browser.collapseNestedTabs(!collapsed, under: tab.id, matching: sourceAssignment)
                    }
                }
            }
        }
    }

    private var sourceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    /// Whether this tab sits in a split the sidebar actually draws as a group.
    ///
    /// Membership alone is not enough: a run shorter than the renderable
    /// minimum keeps its group ID in storage so a staggered sync can
    /// reconstitute the split, but presents as a plain tab. Offering to leave a
    /// group nobody can see would be an action with no visible subject, so the
    /// item is absent rather than dimmed — every other tab in the list is a
    /// tab this menu can act on the same way.
    private var isRenderableSplitMember: Bool {
        context.space.shownSplit(containing: tab.id) != nil
    }

    /// Whether the card has another card `offset` places along its split.
    private func canStepSplitMember(by offset: Int) -> Bool {
        guard offset != 0, context.isCurrent(sourceAssignment),
            let groupID = context.space.shownSplit(containing: tab.id)
        else { return false }
        let members = context.space.splitMembers(of: groupID)
        guard let index = members.firstIndex(where: { $0.id == tab.id }) else { return false }
        return members.indices.contains(index + offset)
    }

    /// The Move to Space item for `space`.
    private func moveButton(to space: SpaceModel) -> some View {
        Button {
            performIfCurrent {
                let destinationAssignment =
                    BrowserSpaceRuntimeAssignment(space: space)
                guard
                    browser.unlockedSpace(matching: destinationAssignment, accessController: spaceAccess)
                        != nil
                else { return }
                browser.moveTab(
                    tab.id,
                    matching: sourceAssignment,
                    into: destinationAssignment
                )
            }
        } label: {
            BrowserSpaceIdentityLabel(space: space)
        }
        .disabled(
            !browser.canMoveTab(
                assignment.tabID,
                matching: sourceAssignment,
                into: BrowserSpaceRuntimeAssignment(space: space)
            )
        )
    }

    private var availableDestinationSpaces: [SpaceModel] {
        browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: spaceAccess)
    }

    /// Runs a menu action only while the window shows the tab's Space,
    /// unlocked, with the profile the menu was built for, and the Space still
    /// holds the tab.
    private func performIfCurrent(_ action: () -> Void) {
        guard context.isCurrent(sourceAssignment), context.space.shownTab(tab.id) != nil else { return }
        action()
    }

    private var organizationAction: BrowserTabOrganizationAction {
        BrowserTabOrganizationAction(
            browser: browser,
            spaceAccess: spaceAccess
        )
    }
}
