import Foundation
import XCTest

@testable import OdeMobile

@MainActor
final class MobileBrowserWindowSceneModelTests: XCTestCase {
    /// iPadOS restores a window scene with the value an earlier build saved,
    /// `{"rawValue": UUID}`. It restores the same window, a bare identity
    /// reads too, and this build saves the spelling an earlier build restores.
    func testAWindowRequestKeepsTheStoredIdentitySpellingAndReadsABareOne() throws {
        let id = UUID()
        let earlier = Data(#"{"rawValue":"\#(id.uuidString)"}"#.utf8)
        let bare = Data(#""\#(id.uuidString)""#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: earlier).id, id)
        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: bare).id, id)
        let stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MobileWindowRequest(id: id)))
        XCTAssertEqual(stored as? [String: String], ["rawValue": id.uuidString])
    }

    /// A link from another app takes the window, so an address the person
    /// was typing closes rather than keeping the keyboard up over the link.
    func testALinkFromAnotherAppEndsAddressEditing() async throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
            usesEphemeralWebsiteDataStores: true)
        let before = model.navigation.addressEditingEndRequests

        let routed = await model.routeExternalURL(try XCTUnwrap(URL(string: "https://example.com/shared")))

        XCTAssertTrue(routed)
        XCTAssertEqual(model.navigation.addressEditingEndRequests, before + 1)
    }

    func testCommandLinkTargetsOnlyReceivingSceneAndCurrentBrowsingModeWithoutNavigating() throws {
        let root = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: root, usesEphemeralWebsiteDataStores: true))
        func makeScene() -> MobileBrowserWindowSceneModel {
            MobileBrowserWindowSceneModel(
                id: UUID(), rootBrowser: root, permissionCenter: BrowserSitePermissionCenter(),
                pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
                windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
                usesEphemeralWebsiteDataStores: true)
        }
        let receiving = makeScene()
        let other = makeScene()
        let standardBefore = receiving.browser.sessionSeed
        let privateBefore = receiving.privateBrowser.sessionSeed
        XCTAssertTrue(receiving.routeCommandURL(BrowserCommandLink.newQuery.url, browsingMode: .privateBrowsing))
        XCTAssertTrue(receiving.privateNavigation.hasPendingFreshQuery)
        XCTAssertFalse(receiving.navigation.hasPendingFreshQuery)
        XCTAssertFalse(other.privateNavigation.hasPendingFreshQuery)
        XCTAssertFalse(other.navigation.hasPendingFreshQuery)
        XCTAssertEqual(receiving.browser.sessionSeed, standardBefore)
        XCTAssertEqual(receiving.privateBrowser.sessionSeed, privateBefore)
        XCTAssertFalse(
            receiving.routeCommandURL(
                try XCTUnwrap(URL(string: "ode://command/new?query=ignored")), browsingMode: .standard))
        XCTAssertFalse(receiving.navigation.hasPendingFreshQuery)
        XCTAssertTrue(receiving.routeCommandURL(BrowserCommandLink.newQuery.url, browsingMode: .standard))
        XCTAssertTrue(receiving.navigation.hasPendingFreshQuery)
    }

    /// A scene that closes takes its private workspace with it, once. Shown
    /// again, it browses privately in a new workspace, never in the closed one.
    func testAClosedSceneClosesItsPrivateWorkspaceAndOpensANewOneWhenShownAgain() throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
            usesEphemeralWebsiteDataStores: true)
        let closing = model.privateBrowser
        let closed = closing.family.workspaceID

        model.closeWindowRuntime()
        model.closeWindowRuntime()

        XCTAssertFalse(closing.family.isOpen)
        XCTAssertNil(rootBrowser.core.state.workspaces[closed])
        model.activateWindow()
        XCTAssertFalse(model.privateBrowser === closing)
        XCTAssertTrue(model.privateBrowser.family.isOpen)
        XCTAssertNotEqual(model.privateBrowser.family.workspaceID, closed)
        let url = try XCTUnwrap(URL(string: "https://private.example"))
        let tab = try XCTUnwrap(model.privateBrowser.openNewTab(url: url))
        XCTAssertTrue(model.privateBrowser.openTabIDs.contains(tab))
    }

}
