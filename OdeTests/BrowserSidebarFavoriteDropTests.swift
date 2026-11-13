import CoreGraphics
import Foundation
import XCTest

@testable import Ode

/// A pinned tile dragged into the open tabs is accepted at the slot the list
/// opened for it, and lands where that slot was drawn without setting off
/// again once the row it became measures itself. Dropped on another Space, it
/// goes into that Space's segment; over the grid, a slot is found at the
/// density the grid is drawn at.
@MainActor
final class BrowserSidebarFavoriteDropTests: XCTestCase {
    func testAFavoriteDroppedBetweenOpenTabsLandsAtTheSlotTheListOpened() throws {
        let fixture = FavoriteDropFixture()
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)
        let item = fixture.item(fixture.pinned[0])

        state.begin(
            item: item, section: .tabs(placement: .pinned, folderID: nil),
            at: CGPoint(x: fixture.tile(0).midX, y: fixture.tile(0).midY), plan: fixture.browser.liftPlan(for: item))
        state.update(pointer: CGPoint(x: 120, y: fixture.row(1).minY + 6))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: .tabs(placement: .current, folderID: nil), beforeID: .tab(fixture.current[1].id), index: 1)
        )

        // The list draws the open slot; the drop lands there.
        let drawnSlot = CGRect(x: 8, y: fixture.row(1).minY, width: 240, height: 40)
        state.noteDrawnSlot(drawnSlot, inGrid: false)
        let drop = try XCTUnwrap(state.end(retainingPreview: true, landingTimeout: nil))
        XCTAssertEqual(state.landingPreview?.landing?.frame, drawnSlot)

        let context = BrowserSidebarReorderContext(
            browser: fixture.browser, spaceAccess: BrowserSpaceAccessController(), state: state)
        XCTAssertTrue(context.commit(drop), "A valid drop is taken at once.")
        let rows = try XCTUnwrap(fixture.browser.spaceModel(fixture.spaceID)).sidebar.section(.current).rows
        XCTAssertEqual(
            rows.map(\.id), [fixture.current[0].id, fixture.pinned[0].id, fixture.current[1].id, fixture.current[2].id])

        // The grid the tile left measures it once more on its way out, which
        // never moves the landing.
        state.register(
            row: fixture.tileRow(fixture.pinned[0], at: 0), owner: fixture.tileOwners[fixture.pinned[0].id]!)
        XCTAssertEqual(state.landingPreview?.landing?.frame, drawnSlot)

        // The row it became measures itself where the slot was: nothing moves.
        let arrived = BrowserSidebarReorderRow(
            id: .tab(fixture.pinned[0].id), space: fixture.assignment,
            section: .tabs(placement: .current, folderID: nil), frame: drawnSlot.offsetBy(dx: 0, dy: 0.5))
        state.register(row: arrived, owner: UUID())
        XCTAssertEqual(state.landingPreview?.landing?.frame, drawnSlot)

        // A later measurement elsewhere does not send the preview off again.
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(fixture.pinned[0].id), space: fixture.assignment,
                section: .tabs(placement: .current, folderID: nil), frame: drawnSlot.offsetBy(dx: 0, dy: 30)),
            owner: UUID())
        XCTAssertEqual(state.landingPreview?.landing?.frame, drawnSlot)
    }

    func testAMeasuredRowAwayFromTheDrawnSlotRetargetsTheLandingOnce() throws {
        let fixture = FavoriteDropFixture()
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)
        let item = fixture.item(fixture.pinned[1])
        state.begin(
            item: item, section: .tabs(placement: .pinned, folderID: nil),
            at: CGPoint(x: fixture.tile(1).midX, y: fixture.tile(1).midY), plan: fixture.browser.liftPlan(for: item))
        state.update(pointer: CGPoint(x: 120, y: fixture.row(2).minY + 6))
        let drawnSlot = CGRect(x: 8, y: fixture.row(2).minY, width: 240, height: 40)
        state.noteDrawnSlot(drawnSlot, inGrid: false)
        _ = try XCTUnwrap(state.end(retainingPreview: true, landingTimeout: nil))

        let measured = drawnSlot.offsetBy(dx: 0, dy: -48)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(fixture.pinned[1].id), space: fixture.assignment,
                section: .tabs(placement: .current, folderID: nil), frame: measured),
            owner: UUID())
        XCTAssertEqual(state.landingPreview?.landing?.frame, measured)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(fixture.pinned[1].id), space: fixture.assignment,
                section: .tabs(placement: .current, folderID: nil), frame: measured.offsetBy(dx: 0, dy: 20)),
            owner: UUID())
        XCTAssertEqual(state.landingPreview?.landing?.frame, measured, "The landing is aimed again only once.")
    }

    func testWithNoSlotDrawnAFavoriteLandsInTheProjectedGapRatherThanOnItsTile() throws {
        let fixture = FavoriteDropFixture()
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)
        let item = fixture.item(fixture.pinned[0])
        state.begin(
            item: item, section: .tabs(placement: .pinned, folderID: nil),
            at: CGPoint(x: fixture.tile(0).midX, y: fixture.tile(0).midY), plan: fixture.browser.liftPlan(for: item))
        state.update(pointer: CGPoint(x: 120, y: fixture.row(1).minY + 6))
        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: .tabs(placement: .current, folderID: nil), beforeID: .tab(fixture.current[1].id), index: 1)
        )

        let drop = try XCTUnwrap(state.end(retainingPreview: true, landingTimeout: nil))
        let landing = try XCTUnwrap(state.landingPreview?.landing?.frame)
        XCTAssertNotEqual(landing, fixture.tile(0), "A valid drop never flies back to where it was lifted.")
        XCTAssertEqual(landing.minX, fixture.row(1).minX)
        XCTAssertEqual(landing.height, fixture.row(1).height, "The gap is as tall as the list's own rows.")
        XCTAssertTrue((fixture.row(0).minY...fixture.row(2).minY).contains(landing.minY))

        let context = BrowserSidebarReorderContext(
            browser: fixture.browser, spaceAccess: BrowserSpaceAccessController(), state: state)
        XCTAssertTrue(context.commit(drop))
        let rows = try XCTUnwrap(fixture.browser.spaceModel(fixture.spaceID)).sidebar.section(.current).rows
        XCTAssertEqual(rows.firstIndex { $0.id == fixture.pinned[0].id }, 1)
    }

    func testAFavoriteDroppedOnAnotherSpaceShrinksIntoItsSegmentAndFades() throws {
        let fixture = FavoriteDropFixture()
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)
        let otherSpace = try XCTUnwrap(fixture.browser.spaceModel(fixture.otherSpaceID))
        let other = BrowserSpaceRuntimeAssignment(space: otherSpace)
        let segment = CGRect(x: 120, y: 420, width: 28, height: 28)
        state.register(zone: BrowserSidebarReorderZone(target: .space(other), frame: segment), for: UUID())
        let item = fixture.item(fixture.pinned[0])
        state.begin(
            item: item, section: .tabs(placement: .pinned, folderID: nil),
            at: CGPoint(x: fixture.tile(0).midX, y: fixture.tile(0).midY), plan: fixture.browser.liftPlan(for: item))
        state.update(pointer: CGPoint(x: segment.midX, y: segment.midY))
        XCTAssertEqual(state.resolvedTarget?.kind, .space(other))

        let drop = try XCTUnwrap(state.end(retainingPreview: true, landingTimeout: nil))
        let landing = try XCTUnwrap(state.landingPreview?.landing)
        XCTAssertEqual(landing.frame, segment)
        XCTAssertTrue(landing.fades, "Nothing takes over from the preview in the segment, so it fades.")

        // The row it became, in the other Space's list, never sends it off again.
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(fixture.pinned[0].id), space: other, section: .tabs(placement: .pinned, folderID: nil),
                frame: CGRect(x: 600, y: 60, width: 80, height: 47)),
            owner: UUID())
        XCTAssertEqual(state.landingPreview?.landing?.frame, segment)

        let context = BrowserSidebarReorderContext(
            browser: fixture.browser, spaceAccess: BrowserSpaceAccessController(), state: state)
        XCTAssertTrue(context.commit(drop), fixture.browser.tabMultiSelection.message ?? "")
        XCTAssertNil(try XCTUnwrap(fixture.browser.spaceModel(fixture.spaceID)).tabs.model(fixture.pinned[0].id))
        XCTAssertTrue(
            try XCTUnwrap(fixture.browser.spaceModel(fixture.otherSpaceID)).tabs.models.contains {
                $0.url == fixture.pinned[0].url
            })
    }

    func testAnOpenTabOverTheGridFindsItsSlotAtTheDensityTheGridIsDrawnAt() throws {
        let scale = BrowserDeviceAppearanceStore.shared.tabScale
        for density in BrowserLayoutDensity.all {
            let fixture = FavoriteDropFixture()
            let state = fixture.sidebarInteraction.sidebarReorderState
            fixture.register(in: state, density: density)
            let item = fixture.item(fixture.current[0])
            state.begin(
                item: item, section: .tabs(placement: .current, folderID: nil),
                at: CGPoint(x: fixture.row(0).midX, y: fixture.row(0).midY),
                plan: fixture.browser.liftPlan(for: item))
            state.update(pointer: CGPoint(x: fixture.tile(1).midX, y: fixture.tile(1).midY))
            guard case .insert(let section, _, _) = state.resolvedTarget?.kind else {
                return XCTFail("An open tab over the grid is aimed into it")
            }
            XCTAssertEqual(section, .tabs(placement: .pinned, folderID: nil))

            _ = try XCTUnwrap(state.end(retainingPreview: true, landingTimeout: nil))
            XCTAssertEqual(
                state.landingPreview?.landing?.frame.height,
                CGFloat(BrowserSidebarDensity(scale, density: density).pinHeight(touch: false)), density.name)
        }
    }
}

// MARK: - Fixture

/// One Space with two pinned tiles in a row and three open tabs below them,
/// and a second, empty Space beside it.
@MainActor
private struct FavoriteDropFixture {
    let browser: BrowserStore
    let sidebarInteraction: BrowserSidebarInteractionState
    let pinned: [TabState.Seed]
    let current: [TabState.Seed]
    let spaceID = UUID()
    let otherSpaceID = UUID()
    let profileID = UUID()
    let tileOwners: [UUID: UUID]

    init() {
        pinned = (0..<2).map {
            TabState.Seed(title: "Pinned \($0)", url: URL(string: "https://pinned\($0).example"), placement: .pinned)
        }
        current = (0..<3).map {
            TabState.Seed(title: "Open \($0)", url: URL(string: "https://open\($0).example"), placement: .current)
        }
        let space = SpaceState.Seed(
            id: spaceID, profileID: profileID, name: "Home", symbol: "house", accent: .indigo, folders: [],
            tabs: pinned + current)
        let other = SpaceState.Seed(
            id: otherSpaceID, profileID: profileID, name: "Work", symbol: "briefcase", accent: .teal, folders: [],
            tabs: [])
        browser = BrowserStore(seed: SessionState.Seed(spaces: [space, other]))
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        tileOwners = Dictionary(uniqueKeysWithValues: pinned.map { ($0.id, UUID()) })
    }

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    func tile(_ index: Int) -> CGRect {
        CGRect(x: 8 + CGFloat(index) * 84, y: 60, width: 80, height: 47)
    }

    func row(_ index: Int) -> CGRect {
        CGRect(x: 8, y: 200 + CGFloat(index) * 40, width: 240, height: 40)
    }

    func item(_ tab: TabState.Seed) -> BrowserSidebarReorderItem {
        .tab(BrowserTabDragItem(tabID: tab.id, spaceID: spaceID, profileID: profileID))
    }

    func tileRow(_ tab: TabState.Seed, at index: Int) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: .tab(tab.id), space: assignment, section: .tabs(placement: .pinned, folderID: nil), frame: tile(index))
    }

    func register(in state: BrowserSidebarReorderState, density: BrowserLayoutDensity = .defaultValue) {
        for (index, tab) in pinned.enumerated() {
            state.register(row: tileRow(tab, at: index), owner: tileOwners[tab.id]!)
        }
        for (index, tab) in current.enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id), space: assignment, section: .tabs(placement: .current, folderID: nil),
                    frame: row(index)),
                owner: UUID())
        }
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(.tabs(placement: .pinned, folderID: nil)),
                frame: CGRect(x: 8, y: 56, width: 240, height: 56), density: density),
            for: UUID())
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(.tabs(placement: .current, folderID: nil)),
                frame: CGRect(x: 8, y: 196, width: 240, height: 128)),
            for: UUID())
    }
}
