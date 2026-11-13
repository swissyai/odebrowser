import Foundation
import XCTest

@testable import Ode

final class BrowserSidebarReorderLayoutTests: XCTestCase {
    private let space = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
    private let source = BrowserSidebarReorderItemID.folder(UUID())
    private let current = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)

    @MainActor
    func testNativeDragCompletionClearsTheMatchingLiftButNotANewerSession() throws {
        let state = BrowserSidebarReorderState()
        let item = BrowserSidebarReorderItem.tab(
            .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
        state.stage(item: item, section: current)
        let first = try XCTUnwrap(state.sessionToken)
        state.update(pointer: CGPoint(x: 50, y: 100))
        XCTAssertEqual(state.sessionToken, first)
        XCTAssertTrue(state.hidesSource(item.id))
        state.cancel(session: first)
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.hidesSource(item.id))
        XCTAssertNil(state.layout.gapFrame)

        state.stage(item: item, section: current)
        let second = try XCTUnwrap(state.sessionToken)
        XCTAssertNotEqual(first, second)
        state.update(pointer: CGPoint(x: 50, y: 100))
        state.cancel(session: first)
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.sessionToken, second)
        state.cancel(session: second)
        XCTAssertFalse(state.hasLiftInFlight)
    }

    func testAdjacentFolderEdgesOfferTheirParentSectionForTabs() {
        for placement in [TabPlacement.saved, .current] {
            let parent = BrowserSidebarReorderSection.tabs(placement: placement, folderID: nil)
            let first = UUID()
            let second = UUID()
            let zones = [
                BrowserSidebarReorderZone(
                    target: .section(parent), frame: CGRect(x: 8, y: 100, width: 240, height: 240)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: first)),
                    frame: CGRect(x: 8, y: 100, width: 240, height: 80)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: second)),
                    frame: CGRect(x: 8, y: 180, width: 240, height: 80)),
            ]
            let item = BrowserSidebarReorderItem.tab(
                .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
            for y in [CGFloat(176), 180, 184] {
                XCTAssertEqual(
                    BrowserSidebarReorderZone.aimed(at: CGPoint(x: 100, y: y), in: zones, accepting: item)?.target,
                    .section(parent))
            }
            XCTAssertEqual(
                BrowserSidebarReorderZone.aimed(at: CGPoint(x: 100, y: 210), in: zones, accepting: item)?.target,
                .section(.tabs(placement: placement, folderID: second)))
        }
    }

    @MainActor
    func testExpandedFolderPassesItsSiblingWithoutDraggingAnEntireFolderHeight() throws {
        let state = BrowserSidebarReorderState()
        let siblingID = UUID()
        let sibling = row(.folder(siblingID), y: 260, height: 80)
        let following = row(.tab(UUID()), y: 340, height: 40)
        for row in [row(source, y: 100, height: 160), sibling, following] {
            state.register(row: row, owner: UUID())
        }
        state.register(
            zone: .init(target: .section(current), frame: CGRect(x: 8, y: 100, width: 240, height: 280)), for: UUID())
        state.register(
            zone: .init(
                target: .section(.folders(parentID: siblingID)),
                frame: CGRect(x: 8, y: 300, width: 240, height: 40)), for: UUID())
        state.begin(
            item: .folder(
                .init(folderID: try XCTUnwrap(source.folderID), spaceID: space.spaceID, profileID: space.profileID)),
            section: current, at: CGPoint(x: 80, y: 120))
        state.update(pointer: CGPoint(x: 80, y: 168))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        // Animation measurements and a held pointer cannot oscillate the slot.
        for _ in 0..<50 {
            state.register(row: row(.folder(siblingID), y: 100, height: 80), owner: UUID())
            state.update(pointer: CGPoint(x: 80, y: 168))
        }
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        state.update(pointer: CGPoint(x: 80, y: 130))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: sibling.id, index: 0))

        state.cancel()
        XCTAssertFalse(state.layout.isActive)
        XCTAssertNil(state.layout.gapFrame)
    }

    private func row(_ id: BrowserSidebarReorderItemID, y: CGFloat, height: CGFloat) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: id, space: space, section: current,
            frame: CGRect(x: 8, y: y, width: 240, height: height))
    }

}
