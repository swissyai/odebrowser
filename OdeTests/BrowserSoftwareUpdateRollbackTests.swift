import CryptoKit
import XCTest

@testable import Ode

/// Going back to an earlier version trusts only what Ode's update key signed,
/// never loses the installed app when a swap fails, and says when the earlier
/// version cannot keep this one's data.
@MainActor
final class BrowserSoftwareUpdateRollbackTests: XCTestCase {
    private let signing = Curve25519.Signing.PrivateKey()

    private var key: BrowserSoftwareUpdateSigningKey {
        BrowserSoftwareUpdateSigningKey(base64: signing.publicKey.rawRepresentation.base64EncodedString())!
    }

    private func signed(_ body: String) throws -> Data {
        let content = Data(body.utf8)
        let signature = try signing.signature(for: content).base64EncodedString()
        return content
            + Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(content.count)\n-->\n".utf8)
    }

    private let feed = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <item>
                    <title>0.9.4</title>
                    <pubDate>Thu, 29 Oct 2026 09:12:00 +0000</pubDate>
                    <sparkle:version>202610290912</sparkle:version>
                    <sparkle:shortVersionString>0.9.4</sparkle:shortVersionString>
                    <sparkle:minimumSystemVersion>26.1</sparkle:minimumSystemVersion>
                    <enclosure url="https://odebrowser.com/updates/Ode-0.9.4.dmg" length="10" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>
                    <sparkle:deltas>
                        <enclosure url="https://odebrowser.com/updates/Ode-0.9.4-from-0.9.3.delta" sparkle:deltaFrom="202610220900" length="3" sparkle:edSignature="ZGVsdGE="/>
                    </sparkle:deltas>
                </item>
                <item>
                    <title>0.9.3</title>
                    <sparkle:version>202610220900</sparkle:version>
                    <enclosure url="https://odebrowser.com/updates/Ode-0.9.3.dmg" length="9" type="application/octet-stream"/>
                </item>
            </channel>
        </rss>
        """

    // MARK: - Trust

    func testOnlyASignedFeedAndSignedFullDownloadsAreOffered() throws {
        let signedFeed = try signed(feed)
        XCTAssertTrue(key.isValidFeed(signedFeed))
        XCTAssertFalse(key.isValidFeed(Data(feed.utf8)), "An unsigned feed")
        var tampered = signedFeed
        tampered[tampered.startIndex + 120] ^= 0x01
        XCTAssertFalse(key.isValidFeed(tampered), "A feed changed after signing")
        let other = Curve25519.Signing.PrivateKey()
        let foreign =
            try Data(feed.utf8)
            + Data(
                "<!-- sparkle-signatures:\nedSignature: \(other.signature(for: Data(feed.utf8)).base64EncodedString())\nlength: \(feed.utf8.count)\n-->\n"
                    .utf8)
        XCTAssertFalse(key.isValidFeed(foreign), "A feed signed with another key")

        let releases = BrowserSoftwareUpdateRelease.releases(inFeed: signedFeed)
        XCTAssertEqual(releases.map(\.build), ["202610290912"], "An item without a signature is never offered")
        XCTAssertEqual(releases.first?.archive.lastPathComponent, "Ode-0.9.4.dmg", "The full download, never a delta")
        XCTAssertEqual(releases.first?.version, "0.9.4")
        XCTAssertNotNil(releases.first?.publishedAt)

        let image = Data("a disk image".utf8)
        let signature = try signing.signature(for: image).base64EncodedString()
        XCTAssertTrue(key.isValid(signature: signature, for: image))
        XCTAssertFalse(key.isValid(signature: signature, for: Data("another disk image".utf8)))
    }

    func testASparkleOneFeedNamesItsVersionsOnTheEnclosure() {
        let feed = Data(
            """
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
            <title>Ode 0.8.1</title>
            <enclosure url="https://odebrowser.com/updates/Ode-0.8.1.dmg" sparkle:version="202609010000"
              sparkle:shortVersionString="0.8.1" length="12" sparkle:edSignature="c2ln" type="application/octet-stream"/>
            </item></channel></rss>
            """.utf8)
        let release = BrowserSoftwareUpdateRelease.releases(inFeed: feed).first
        XCTAssertEqual(release?.build, "202609010000")
        XCTAssertEqual(release?.version, "0.8.1")
        XCTAssertEqual(release?.length, 12)
    }

    func testOnlyEarlierBuildsThisMacCanRunOnItsChannelsAreOffered() throws {
        let release = try XCTUnwrap(BrowserSoftwareUpdateRelease.releases(inFeed: signed(feed)).first)
        XCTAssertTrue(release.isOlder(thanBuild: "202611021013"))
        XCTAssertFalse(release.isOlder(thanBuild: "202610290912"))
        XCTAssertTrue(release.runs(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)))
        XCTAssertFalse(release.runs(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 3)))
        XCTAssertTrue(release.belongs(to: []))
    }

    // MARK: - Data

    func testGoingBackWarnsOnlyWhenTheEarlierVersionCannotKeepThisOnesData() {
        let installation = installation(
            at: URL(fileURLWithPath: "/Applications/Ode.app"), storage: 2, engine: "156.0.1")
        XCTAssertEqual(
            installation.warnings(
                goingBackTo: [
                    "OdeSessionStorageVersion": 2, "OdeSessionJournalVersion": 1,
                    "OdeChromiumEngineVersion": "156.0.0",
                ],
                version: "0.9.3"),
            [])
        let older = installation.warnings(goingBackTo: ["OdeChromiumEngineVersion": "155.0.8059.84"], version: "0.8.80")
        XCTAssertEqual(older.count, 2, "A build without the keys reads storage version 1, and an older engine")
    }

    func testTheSwapWaitsForOdeToQuitAndNeverLosesTheInstalledApp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("Applications/Ode.app", isDirectory: true)
        let staging = folder.appendingPathComponent("Staging", isDirectory: true)
        let staged = staging.appendingPathComponent("Ode.app", isDirectory: true)
        for (bundle, marker) in [(installed, "current"), (staged, "earlier")] {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: bundle.appendingPathComponent("marker"))
        }
        let exited = Process()
        exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try exited.run()
        exited.waitUntilExit()

        let swap = try installation(at: installed).replace(
            with: staged, afterExitOf: exited.processIdentifier, reopen: false)
        swap.waitUntilExit()
        XCTAssertEqual(swap.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "earlier")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [], "Nothing is left behind")

        let failed = try installation(at: installed).replace(
            with: staging.appendingPathComponent("Missing.app"), afterExitOf: exited.processIdentifier, reopen: false)
        failed.waitUntilExit()
        XCTAssertNotEqual(failed.terminationStatus, 0)
        XCTAssertEqual(
            try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "earlier",
            "A swap that fails puts the installed app back")
    }

    private func installation(at url: URL, storage: Int = 1, engine: String? = nil) -> BrowserSoftwareUpdateInstallation
    {
        BrowserSoftwareUpdateInstallation(
            bundleURL: url, bundleIdentifier: "com.odebrowser.ode", version: "0.9.4", build: "202610290912",
            team: "TEAM", sessionVersions: ["OdeSessionStorageVersion": storage, "OdeSessionJournalVersion": 1],
            engineVersion: engine)
    }
}
