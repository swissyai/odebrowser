import Foundation

/// The native-messaging hosts the Chromium engine finds in its own folder.
///
/// A companion app, such as a password manager's desktop app, registers its
/// host only in the folders of the browsers it knows: Chrome, Chromium, Arc,
/// Brave, Edge, Vivaldi and a few more, and only when that browser's folder
/// already exists. The engine looks in its own profile folder first, so Ode
/// links each registration it finds in those folders there, under the same
/// name. Chromium still reads each registration and answers only the
/// extensions it lists, so a link grants nothing the companion app did not.
///
/// A registration the person or an administrator placed in the folder
/// themselves is never replaced. A link Ode made is pointed again at the
/// first folder that still holds that registration, and removed once none
/// does.
struct BrowserNativeMessagingHosts {
    // MARK: - Static Variables

    /// Where each browser keeps its per-user registrations, under the
    /// person's Application Support folder, in the order a registration is
    /// taken from. Chrome's comes first, as the engine's own fallback reads it.
    static let browserFolders = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary", "Chromium",
        "Arc/User Data", "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser-Beta",
        "BraveSoftware/Brave-Browser-Nightly", "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev",
        "Microsoft Edge Canary", "Vivaldi", "net.imput.helium", "Thorium",
    ]

    // MARK: - Variables

    /// The engine profile's own registration folder.
    let folder: URL
    /// The folders registrations are linked from, first match first.
    let sources: [URL]

    // MARK: - Initializers

    /// The registrations of the engine whose profiles live in `userData`,
    /// linked from the browsers' folders under `applicationSupport`.
    init(userData: URL, applicationSupport: URL) {
        folder = userData.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        sources = Self.browserFolders.map {
            applicationSupport.appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        }
    }

    // MARK: - Actions - Linking

    /// Links every registration the browsers' folders hold that the engine's
    /// folder lacks, re-points the links Ode made before, and removes those
    /// whose registration is gone. Answers the names linked now.
    @discardableResult
    func link(fileManager: FileManager = .default) -> [String] {
        var found: [String: URL] = [:]
        for source in sources {
            for name in (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
            where Self.isRegistration(name) && found[name] == nil {
                let file = source.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: file.path) else { continue }
                found[name] = file
            }
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        where Self.isRegistration(name) && found[name] == nil {
            let entry = folder.appendingPathComponent(name)
            if isOwnLink(entry, fileManager: fileManager) { try? fileManager.removeItem(at: entry) }
        }
        guard !found.isEmpty else { return [] }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var linked: [String] = []
        for (name, file) in found.sorted(by: { $0.key < $1.key }) {
            let entry = folder.appendingPathComponent(name)
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: entry.path) {
                guard isOwnLink(entry, fileManager: fileManager), target != file.path else { continue }
                try? fileManager.removeItem(at: entry)
            } else if fileManager.fileExists(atPath: entry.path) {
                continue
            }
            if (try? fileManager.createSymbolicLink(at: entry, withDestinationURL: file)) != nil {
                linked.append(name)
            }
        }
        return linked
    }

    /// Whether `entry` is a link Ode made: one into a browser's folder.
    private func isOwnLink(_ entry: URL, fileManager: FileManager) -> Bool {
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: entry.path) else { return false }
        let parent = URL(fileURLWithPath: target).deletingLastPathComponent().standardizedFileURL.path
        return sources.contains { $0.standardizedFileURL.path == parent }
    }

    /// Whether `name` names a host registration as Chromium looks one up:
    /// the host's name, in lowercase letters, digits, underscores and dots,
    /// then `.json`.
    static func isRegistration(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let host = name.dropLast(5)
        return !host.isEmpty && host.first != "." && host.last != "."
            && host.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "." }
    }
}
