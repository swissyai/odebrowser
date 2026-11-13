import Foundation
import XCTest

@testable import Ode

/// The engine finds a companion app's native-messaging host in its own
/// profile folder through links to the registrations other browsers hold.
final class BrowserNativeMessagingHostsTests: XCTestCase {
    private let fileManager = FileManager.default

    func testLinksEachRegistrationFromTheFirstBrowserFolderThatHoldsIt() throws {
        let root = try temporaryFolder()
        defer { try? fileManager.removeItem(at: root) }
        let hosts = hosts(in: root)
        let chrome = try register("com.8bit.bitwarden", in: "Google/Chrome", root: root)
        _ = try register("com.8bit.bitwarden", in: "Arc/User Data", root: root)
        let arc = try register("com.1password.1password", in: "Arc/User Data", root: root)
        _ = try register("Not.A.Host", in: "Vivaldi", root: root)

        XCTAssertEqual(
            hosts.link(fileManager: fileManager), ["com.1password.1password.json", "com.8bit.bitwarden.json"])

        XCTAssertEqual(try target(of: "com.8bit.bitwarden.json", in: hosts), chrome.path)
        XCTAssertEqual(try target(of: "com.1password.1password.json", in: hosts), arc.path)
        XCTAssertFalse(fileManager.fileExists(atPath: hosts.folder.appendingPathComponent("Not.A.Host.json").path))
        XCTAssertEqual(hosts.link(fileManager: fileManager), [], "A second pass changes nothing")
    }

    func testNeverReplacesARegistrationPlacedByHand() throws {
        let root = try temporaryFolder()
        defer { try? fileManager.removeItem(at: root) }
        let hosts = hosts(in: root)
        _ = try register("com.8bit.bitwarden", in: "Google/Chrome", root: root)
        try fileManager.createDirectory(at: hosts.folder, withIntermediateDirectories: true)
        let placed = hosts.folder.appendingPathComponent("com.8bit.bitwarden.json")
        try Data(#"{"name":"com.8bit.bitwarden"}"#.utf8).write(to: placed)

        XCTAssertEqual(hosts.link(fileManager: fileManager), [])

        XCTAssertNil(try? fileManager.destinationOfSymbolicLink(atPath: placed.path))
        XCTAssertEqual(try String(contentsOf: placed, encoding: .utf8), #"{"name":"com.8bit.bitwarden"}"#)
    }

    func testFollowsARegistrationThatMovesAndDropsOneThatIsGone() throws {
        let root = try temporaryFolder()
        defer { try? fileManager.removeItem(at: root) }
        let hosts = hosts(in: root)
        let brave = try register("me.proton.pass.nm", in: "BraveSoftware/Brave-Browser", root: root)
        let edge = try register("com.example.gone", in: "Microsoft Edge", root: root)
        let elsewhere = root.appendingPathComponent("elsewhere.json")
        try Data("{}".utf8).write(to: elsewhere)
        try fileManager.createDirectory(at: hosts.folder, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: hosts.folder.appendingPathComponent("com.example.own.json"), withDestinationURL: elsewhere)
        hosts.link(fileManager: fileManager)
        XCTAssertEqual(try target(of: "me.proton.pass.nm.json", in: hosts), brave.path)

        let chrome = try register("me.proton.pass.nm", in: "Google/Chrome", root: root)
        try fileManager.removeItem(at: edge)
        XCTAssertEqual(hosts.link(fileManager: fileManager), ["me.proton.pass.nm.json"])

        XCTAssertEqual(try target(of: "me.proton.pass.nm.json", in: hosts), chrome.path)
        XCTAssertNil(try? target(of: "com.example.gone.json", in: hosts))
        XCTAssertEqual(
            try target(of: "com.example.own.json", in: hosts), elsewhere.path, "A link Ode did not make stays")
    }

    // MARK: - Support

    private func hosts(in root: URL) -> BrowserNativeMessagingHosts {
        BrowserNativeMessagingHosts(
            userData: root.appendingPathComponent("Crest/Chromium", isDirectory: true),
            applicationSupport: root)
    }

    private func register(_ host: String, in browser: String, root: URL) throws -> URL {
        let folder = root.appendingPathComponent(browser).appendingPathComponent("NativeMessagingHosts")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(host + ".json")
        try Data(#"{"name":"\#(host)","path":"/Applications/Example.app/host","type":"stdio"}"#.utf8).write(to: file)
        return file
    }

    private func target(of name: String, in hosts: BrowserNativeMessagingHosts) throws -> String {
        try fileManager.destinationOfSymbolicLink(atPath: hosts.folder.appendingPathComponent(name).path)
    }

    private func temporaryFolder() throws -> URL {
        let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
