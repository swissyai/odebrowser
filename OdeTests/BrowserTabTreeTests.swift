import Foundation
import XCTest

@testable import Ode

/// Open tabs nested under the tab whose page opened them: how the sidebar
/// lists them, and how a modified link and a drop on an open tab nest them
/// while the app nests tabs.
@MainActor
final class BrowserTabTreeTests: XCTestCase {
    func testTheSidebarIndentsNestedTabsAndLeavesOutTheOnesACollapsedTabHides() throws {
        let parent = Self.open("Parent")
        let child = Self.open("Child", under: parent.id)
        let grandchild = Self.open("Grandchild", under: child.id)
        let next = Self.open("Next")

        let items = try Self.items(of: [parent, child, grandchild, next])
        XCTAssertEqual(items.map(\.id), [parent, child, grandchild, next].map { .tab($0.id) })
        XCTAssertEqual(items[0].tree, BrowserSidebarTabTree(depth: 0, nestedTabs: 2, collapsesNestedTabs: false))
        XCTAssertEqual(items[1].tree, BrowserSidebarTabTree(depth: 1, nestedTabs: 1, collapsesNestedTabs: false))
        XCTAssertEqual(items[2].tree?.leadingInset, BrowserSidebarTabTree.indent * 2)
        XCTAssertNil(items[3].tree, "A tab in no tree draws as it always has.")

        var collapsed = child
        collapsed.collapsesNestedTabs = true
        let hidden = try Self.items(of: [parent, collapsed, grandchild, next])
        XCTAssertEqual(hidden.map(\.id), [parent, child, next].map { .tab($0.id) })
        XCTAssertEqual(hidden[1].tree?.collapsesNestedTabs, true)
        XCTAssertEqual(hidden[1].tree?.nestedTabs, 1)
    }

    func testShowingATabACollapsedTabHidesShowsTheTabsAboveIt() throws {
        let parent = Self.open("Parent")
        var child = Self.open("Child", under: parent.id)
        child.collapsesNestedTabs = true
        let grandchild = Self.open("Grandchild", under: child.id)
        var collapsedParent = parent
        collapsedParent.collapsesNestedTabs = true
        let (store, space) = Self.store([collapsedParent, child, grandchild])

        store.selectSpace(space.id)
        XCTAssertTrue(store.activateSessionTab(grandchild.id, in: space.id))
        let model = try XCTUnwrap(store.spaceModel(space.id))
        XCTAssertFalse(try XCTUnwrap(model.tabs.model(parent.id)).collapsesNestedTabs)
        XCTAssertFalse(try XCTUnwrap(model.tabs.model(child.id)).collapsesNestedTabs)
        XCTAssertFalse(model.sidebar.section(.current).rows.contains { $0.isHiddenInTree })
    }

    func testAModifiedLinkNestsUnderTheTabWhosePageFollowedItWhileTabsNest() throws {
        let first = Self.open("First")
        let second = Self.open("Second")
        let (store, space) = Self.store([first, second])
        let link = try XCTUnwrap(URL(string: "https://link.example/"))

        let loose = try XCTUnwrap(store.openModifiedLink(link, in: space.id, selecting: false, openedFrom: first.id))
        XCTAssertNil(loose.tab.parentTabID, "Tabs nest only once the person chooses it.")
        XCTAssertEqual(
            try XCTUnwrap(store.spaceModel(space.id)).sidebar.section(.current).rows.first?.id, loose.tab.id,
            "A tab a page opens goes to the top of the open tabs, as every new tab does.")

        Self.nestTabs(in: store)
        XCTAssertTrue(store.nestsTabs)
        let nested = try XCTUnwrap(store.openModifiedLink(link, in: space.id, selecting: false, openedFrom: first.id))
        XCTAssertEqual(nested.tab.parentTabID, first.id)
        let rows = try XCTUnwrap(store.spaceModel(space.id)).sidebar.section(.current).rows
        XCTAssertEqual(rows.first { $0.id == nested.tab.id }?.treeDepth, 1)
    }

    func testADropOnAnOpenTabNestsUnderItWhileTabsNestAndMakesAFolderOtherwise() throws {
        let tabs = ["A", "B", "C", "D"].map { Self.open($0) }
        let (store, space) = Self.store(tabs)
        func item(_ tab: TabState.Seed) -> BrowserSidebarReorderItem {
            .tab(BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID))
        }

        XCTAssertTrue(store.sidebarDrop(item(tabs[1]), on: .createCurrentFolder(tabs[0].id)))
        XCTAssertNotNil(store.spaceModel(space.id)?.tabs.model(tabs[1].id)?.folderID)

        Self.nestTabs(in: store)
        XCTAssertTrue(store.sidebarDrop(item(tabs[2]), on: .createCurrentFolder(tabs[3].id)))
        let nested = try XCTUnwrap(store.spaceModel(space.id)?.tabs.model(tabs[2].id))
        XCTAssertEqual(nested.parentTabID, tabs[3].id)
        XCTAssertNil(nested.folderID)
    }

    // MARK: - Fixtures

    private static func open(_ title: String, under parent: UUID? = nil) -> TabState.Seed {
        TabState.Seed(
            title: title, url: URL(string: "https://\(title.lowercased()).example/"), placement: .current,
            parentTabID: parent)
    }

    private static func store(_ tabs: [TabState.Seed]) -> (BrowserStore, SpaceState.Seed) {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = tabs
        return (BrowserStore(seed: SessionState.Seed(spaces: [space], defaultSpaceID: space.id)), space)
    }

    private static func items(of tabs: [TabState.Seed]) throws -> [BrowserSidebarListItem] {
        let (store, space) = store(tabs)
        let model = try XCTUnwrap(store.spaceModel(space.id))
        return BrowserSidebarListItem.items(of: model.sidebar.section(.current), in: model)
    }

    /// Turns on nesting tabs opened from pages in `store`'s workspace.
    private static func nestTabs(in store: BrowserStore) {
        var preferences = store.workspaceModel?.appPreferences ?? .default
        preferences.nestsTabsOpenedFromPages = true
        XCTAssertTrue(
            store.sendAppPreferences(
                SetAppPreferences(workspaceID: store.family.workspaceID, preferences: preferences)))
    }
}
