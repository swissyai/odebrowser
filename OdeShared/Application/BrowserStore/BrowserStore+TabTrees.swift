import Foundation

// MARK: - Nested tabs

extension BrowserStore {
    /// The most tabs one tab nests under, as the core keeps trees.
    private static let deepestNesting = 16

    /// Whether a tab a page opens nests under the tab of that page, and a tab
    /// dropped on an open tab nests under it, as the app's preferences say.
    var nestsTabs: Bool {
        (workspaceModel?.appPreferences ?? BrowserAppPreferenceStore.shared.preferences).nestsTabsOpenedFromPages
    }

    /// Hides the tabs nested under the open tab `tabID` of the Space
    /// `assignment` names, or shows them, and answers whether the core took it.
    @discardableResult
    func collapseNestedTabs(
        _ collapsed: Bool, under tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            CollapseNestedTabs(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, tabID: tabID, collapsed: collapsed),
            from: self)
    }

    /// Nests the open tab `tabID` under the tab above it at its level.
    @discardableResult
    func indentTab(_ tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            IndentTab(workspaceID: family.workspaceID, spaceID: assignment.spaceID, tabID: tabID), from: self)
    }

    /// Moves the nested tab `tabID`, with the tabs nested under it, out one
    /// level.
    @discardableResult
    func outdentTab(_ tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            OutdentTab(workspaceID: family.workspaceID, spaceID: assignment.spaceID, tabID: tabID), from: self)
    }

    /// Shows the tabs nested under each collapsed tab above `tabID`, so the
    /// sidebar lists the tab the window shows.
    func revealNestedTab(_ tabID: UUID, in spaceID: UUID) {
        guard let space = spaceModel(spaceID),
            space.sidebar.section(.current).rows.contains(where: { $0.id == tabID && $0.isHiddenInTree })
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        var above = space.tabs.model(tabID)?.parentTabID
        for _ in 0..<Self.deepestNesting {
            guard let parent = above, let tab = space.tabs.model(parent) else { return }
            if tab.collapsesNestedTabs { collapseNestedTabs(false, under: parent, matching: assignment) }
            above = tab.parentTabID
        }
    }

    /// Whether any open tab of `space` nests under `tabID`.
    func holdsNestedTabs(_ tabID: UUID, in space: SpaceModel) -> Bool {
        space.tabs.models.contains { $0.parentTabID == tabID }
    }
}
