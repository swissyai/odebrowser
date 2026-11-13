import XCTest

@testable import Ode

/// The namespace this file's fixed identifiers share.
private let idNamespace = "SIDEBARACCESS"

@MainActor
final class BrowserStoreSidebarAccessTests: XCTestCase {
    func testLockedSelectedSpaceHidesItsActionsUntilItIsUnlocked() async throws {
        let context = makeContext(sourceIsProtected: true)

        XCTAssertFalse(
            context.browser.showsSelectedSpaceActions(accessController: context.access)
        )
        let didUnlock = await context.access.unlock(try XCTUnwrap(context.browser.spaceModel(context.source.id)))
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(
            context.browser.showsSelectedSpaceActions(accessController: context.access)
        )
    }

    func testDeletingSpaceIsExcludedFromPickerAndDropDestinations() {
        let context = makeContext()
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertEqual(
            context.browser.availableSpaces
                .map(\.id),
            [context.source.id]
        )
        XCTAssertNil(
            context.browser.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination), accessController: context.access)
        )
    }

    func testLockedDestinationRemainsVisibleButRejectsTabDrops() {
        let context = makeContext(destinationIsProtected: true)

        XCTAssertEqual(
            context.browser.availableSpaces
                .map(\.id),
            [context.source.id, context.destination.id]
        )
        XCTAssertNil(
            context.browser.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination), accessController: context.access)
        )
    }

    func testTabMoveDestinationsIncludeOnlyExactCurrentlyUnlockedAssignments() async throws {
        let context = makeContext(destinationIsProtected: true)
        let sourceAssignment = BrowserSpaceRuntimeAssignment(space: context.source)

        XCTAssertTrue(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .isEmpty
        )

        let didUnlockDestination = await context.access.unlock(
            try XCTUnwrap(context.browser.spaceModel(context.destination.id)))
        XCTAssertTrue(didUnlockDestination)
        XCTAssertEqual(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .map(\.id),
            [context.destination.id]
        )

        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }
        XCTAssertTrue(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .isEmpty
        )
    }

    private func makeContext(
        sourceIsProtected: Bool = false,
        destinationIsProtected: Bool = false
    ) -> Context {
        let source = makeSpace(
            id: 1,
            profileID: 2,
            name: "Source",
            isProtected: sourceIsProtected
        )
        let destination = makeSpace(
            id: 3,
            profileID: 4,
            name: "Destination",
            isProtected: destinationIsProtected
        )
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]))
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        browser.attachSpaceAccess(access)
        return Context(
            browser: browser,
            access: access,
            source: source,
            destination: destination
        )
    }

    private func makeSpace(
        id: UInt8,
        profileID: UInt8,
        name: String,
        isProtected: Bool
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            id: UUID.fixed(id, namespace: idNamespace),
            profileID: UUID.fixed(profileID, namespace: idNamespace),
            name: name,
            symbol: "square.grid.2x2",
            accent: .indigo,
            folders: [],
            tabs: [],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open
        )
    }

    private struct Context {
        let browser: BrowserStore
        let access: BrowserSpaceAccessController
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
    }
}
