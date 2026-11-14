import Foundation

// MARK: - Types

struct BrowserAboutLicenseDocument: Identifiable, Sendable {
    let id: String
    let text: String?
}

private struct BrowserAboutLicenseInventory: Decodable {
    struct Dependency: Decodable {
        let notice: String
    }

    let runtimeDependencies: [Dependency]
    let bundledData: [Dependency]
    let bundledComponents: [Dependency]
}

/// Reads the canonical notices copied by the app's legal-resource template.
struct BrowserAboutLicenses: Sendable {
    // MARK: - Static Variables

    static let bundled = BrowserAboutLicenses(bundle: .main)

    // MARK: - Variables

    let documents: [BrowserAboutLicenseDocument]

    // MARK: - Initializers

    init(bundle: Bundle) {
        let root = bundle.resourceURL
        var unavailablePaths = Set<String>()
        var paths = [
            "LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "TRADEMARKS.md",
            "SFSymbolCatalog-LICENSE.txt", "HeraldicArtworkCredits.txt", "Mori-LICENSE",
        ]
        if let inventoryURL = root?.appendingPathComponent("ThirdPartyDependencies.json"),
            let data = try? Data(contentsOf: inventoryURL),
            let inventory = try? JSONDecoder().decode(BrowserAboutLicenseInventory.self, from: data)
        {
            let dependencies = inventory.runtimeDependencies + inventory.bundledData + inventory.bundledComponents
            paths += dependencies.map { $0.notice.replacingOccurrences(of: "OdeShared/Resources/", with: "") }
        } else {
            paths.append("ThirdPartyDependencies.json")
            unavailablePaths.insert("ThirdPartyDependencies.json")
        }
        let thirdParty = root?.appendingPathComponent("ThirdParty", isDirectory: true)
        if let thirdParty,
            let files = try? FileManager.default.contentsOfDirectory(
                at: thirdParty, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
            !files.isEmpty
        {
            paths += files.map { "ThirdParty/" + $0.lastPathComponent }.sorted()
        } else {
            // Keep a failed collection visible rather than presenting an empty success.
            paths.append("ThirdParty")
            unavailablePaths.insert("ThirdParty")
        }
        var seen = Set<String>()
        documents = paths.filter { seen.insert($0).inserted }
            .map { path in
                let text =
                    unavailablePaths.contains(path)
                    ? nil
                    : root.flatMap { try? String(contentsOf: $0.appendingPathComponent(path), encoding: .utf8) }
                return BrowserAboutLicenseDocument(
                    id: path,
                    text: text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                )
            }
    }
}
