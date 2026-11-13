import Foundation
import XCTest

@testable import Ode

@MainActor
final class BrowserSpaceBrandingTests: XCTestCase {
    func testMovedChoicesKeepTheirKeysAndWaitToBeWritten() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3.5, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        defaults.set(20.0, forKey: BrowserDeviceAppearanceStore.sidebarRevealWidthKey)
        defaults.set(1.2, forKey: BrowserSidebarDensityPreference.scaleKey)
        defaults.set(true, forKey: BrowserSidebarDensityPreference.pinsFillRowKey)
        defaults.set(false, forKey: BrowserFolderAppearancePreference.showsTabCountsKey)

        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(appearance.windowBorderWidth, 3.5)
        XCTAssertTrue(appearance.sidebarOnRight)
        XCTAssertEqual(appearance.sidebarRevealWidth, 20)
        XCTAssertEqual(appearance.tabScale, 1.2)
        XCTAssertTrue(appearance.pinsFillRow)
        XCTAssertFalse(appearance.foldersShowTabCounts)

        // A drag writes nothing until the choices settle: every write to these
        // defaults makes each @AppStorage view over them re-check its value.
        appearance.windowBorderWidth = 0
        appearance.tabs.hoverFill = 0.5
        XCTAssertEqual(defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), 3.5)
        XCTAssertTrue(appearance.isBorderless)

        appearance.saveNow()
        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.windowBorderWidth, 0)
        XCTAssertTrue(restored.isBorderless)
        XCTAssertEqual(restored.tabs.hoverFill, 0.5)
    }

    func testAddressPlacementDefaultsAndSurvivesLocalAppearancePersistence() throws {
        let name = "crest-test-address-placement-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(BrowserDeviceAppearanceStore(defaults: defaults).address.placement, .top)

        // Earlier versions saved address styling without a placement. Unknown
        // or malformed future values must not discard that existing styling.
        for payload in [
            #"{"fill":0.25,"showsCopyURLButton":true}"#,
            #"{"fill":0.25,"showsCopyURLButton":true,"placement":"future"}"#,
            #"{"fill":0.25,"showsCopyURLButton":true,"placement":42}"#,
        ] {
            defaults.set(Data(payload.utf8), forKey: BrowserDeviceAppearanceStore.addressKey)
            let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
            XCTAssertEqual(appearance.address.placement, .top)
            XCTAssertEqual(appearance.address.fill, 0.25)
            XCTAssertTrue(appearance.address.showsCopyURLButton)
        }

        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        for placement in BrowserAddressPlacement.all {
            appearance.address.placement = placement
            appearance.saveNow()
            let restored = BrowserDeviceAppearanceStore(defaults: defaults)
            XCTAssertEqual(restored.address.placement, placement)
            XCTAssertEqual(restored.address.fill, 0.25)
            XCTAssertTrue(restored.address.showsCopyURLButton)
        }
    }

    /// Stored choices are read back bounded, unreadable ones fall back to
    /// their defaults, and the corner radius kept inside the old tab choices
    /// moves to its own key once.
    func testStoredChoicesAreBoundedAndTheLegacyCornerRadiusMovesOnce() throws {
        func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
            let name = "crest-test-appearance-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            try body(defaults)
        }
        let shares = BrowserTransientCardArrangement.pointerCardShares

        try withDefaults { defaults in
            let empty = BrowserDeviceAppearanceStore(defaults: defaults)
            XCTAssertEqual(empty.cornerRadius, BrowserLookAndFeelDefaults.cornerRadius)
            XCTAssertEqual(defaults.double(forKey: BrowserDeviceAppearanceStore.cornerRadiusKey), empty.cornerRadius)
            XCTAssertEqual(empty.peekSize, shares.upperBound)
            XCTAssertEqual(empty.surfaceMaterial, BrowserLookAndFeelDefaults.surfaceMaterial)
            XCTAssertEqual(empty.mode, BrowserLookAndFeelDefaults.appearanceMode)
            XCTAssertEqual(empty.spaceIconSizing, BrowserLookAndFeelDefaults.spaceIconSizing)
            XCTAssertEqual(empty.spaceIconScale, BrowserLookAndFeelDefaults.spaceIconScale)
            XCTAssertEqual(empty.tabScale, BrowserLookAndFeelDefaults.tabScale)
            XCTAssertEqual(empty.pinColumns, BrowserLookAndFeelDefaults.pinColumns)
            XCTAssertEqual(empty.windowBorderWidth, BrowserLookAndFeelDefaults.windowBorderWidth)
            XCTAssertEqual(empty.foldersTintTitle, BrowserLookAndFeelDefaults.foldersTintTitle)
        }
        for (legacy, migrated) in [(24.0, BrowserDeviceAppearanceStore.maximumCornerRadius), (9, 9), (90, 90)] {
            try withDefaults { defaults in
                let tabs = try JSONSerialization.data(withJSONObject: ["cornerRadius": legacy, "hoverFill": 0.25])
                defaults.set(tabs, forKey: BrowserDeviceAppearanceStore.tabsKey)
                let store = BrowserDeviceAppearanceStore(defaults: defaults)
                XCTAssertEqual(store.cornerRadius, migrated)
                XCTAssertEqual(store.tabs.hoverFill, 0.25)
                XCTAssertEqual(
                    defaults.double(forKey: BrowserDeviceAppearanceStore.cornerRadiusKey),
                    min(migrated, BrowserDeviceAppearanceStore.maximumCornerRadius))
                defaults.set(12.0, forKey: BrowserDeviceAppearanceStore.cornerRadiusKey)
                XCTAssertEqual(BrowserDeviceAppearanceStore(defaults: defaults).cornerRadius, 12)
            }
        }
        try withDefaults { defaults in
            let chromeName = "crest-test-chrome-" + UUID().uuidString
            let chrome = try XCTUnwrap(UserDefaults(suiteName: chromeName))
            defer { chrome.removePersistentDomain(forName: chromeName) }
            chrome.set(2.0, forKey: BrowserChromeAppearancePreference.borderWidthKey)
            chrome.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
            defaults.set(false, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
            defaults.set(7.0, forKey: BrowserChromeAppearancePreference.borderWidthKey)
            defaults.set(Double.nan, forKey: BrowserDeviceAppearanceStore.peekSizeKey)
            defaults.set(Double.infinity, forKey: BrowserSidebarDensityPreference.scaleKey)
            defaults.set(1000.0, forKey: BrowserDeviceAppearanceStore.spaceIconScaleKey)
            defaults.set(3, forKey: BrowserSidebarDensityPreference.pinColumnsKey)
            defaults.set("unknown", forKey: BrowserDeviceAppearanceStore.modeKey)
            defaults.set(Data("{".utf8), forKey: BrowserDeviceAppearanceStore.addressKey)
            defaults.set(true, forKey: BrowserFolderAppearancePreference.iconOnlyKey)
            let store = BrowserDeviceAppearanceStore(defaults: defaults, chrome: chrome)
            XCTAssertEqual(store.windowBorderWidth, 2)
            XCTAssertTrue(store.sidebarOnRight)
            XCTAssertEqual(store.peekSize, shares.upperBound)
            XCTAssertEqual(store.tabScale, BrowserLookAndFeelDefaults.tabScale)
            XCTAssertEqual(store.spaceIconScale, Double(BrowserSpaceIconSizing.clamped(1000)))
            XCTAssertEqual(store.pinColumns, 3)
            XCTAssertEqual(store.mode, BrowserLookAndFeelDefaults.appearanceMode)
            XCTAssertFalse(store.address.showsCopyURLButton)
            XCTAssertTrue(store.foldersIconOnly)
            defaults.set(shares.lowerBound - 1, forKey: BrowserDeviceAppearanceStore.peekSizeKey)
            XCTAssertEqual(BrowserDeviceAppearanceStore(defaults: defaults).peekSize, shares.lowerBound)
        }
    }
}
