#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's site icon commands: bring a Space as an import from
    /// another browser leaves it, its pinned and saved tabs never loaded, and
    /// measure what icon lookups find for a list of pages.
    extension BrowserMacHarness {
        // MARK: - Actions - Imports

        /// Imports a Space named `name` in the `preset` color whose `pinned`
        /// and `saved` addresses never loaded, as importing them from another
        /// browser does, and shows it. Each tab is titled with its site.
        func importUnloadedSpace(_ arguments: [String: Any]) throws -> [String: Any] {
            let browser = try context().browser
            let preset = SpaceColorPreset.all.first { $0.name == arguments["preset"] as? String } ?? .azure
            let pinned = (arguments["pinned"] as? [String] ?? []).compactMap(URL.init(string:))
            let saved = (arguments["saved"] as? [String] ?? []).compactMap(URL.init(string:))
            let tabs =
                pinned.map { TabState.Seed(title: $0.host() ?? $0.absoluteString, url: $0, placement: .pinned) }
                + saved.map { TabState.Seed(title: $0.host() ?? $0.absoluteString, url: $0, placement: .saved) }
                + [.startPage()]
            let space = SpaceState.Seed(
                name: arguments["name"] as? String ?? "Imported", symbol: "star.fill", branding: preset.branding,
                tabs: tabs)
            let before = Set(browser.spaceModels.map(\.id))
            do {
                try browser.family.commit(
                    ImportSpaces(workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaces: [space]),
                    from: browser)
            } catch {
                throw Failure(description: "The core refused the import: \(error)")
            }
            guard let imported = browser.spaceModels.first(where: { !before.contains($0.id) }) else {
                throw Failure(description: "The import brought no Space")
            }
            browser.selectSpace(imported.id)
            return ["spaceID": imported.id.uuidString, "tabs": imported.tabs.models.count]
        }

        // MARK: - Actions - Measuring

        /// Looks up the icon of each of `urls` both ways, a fresh lookup with
        /// nothing remembered, and saves each icon the head lookup found in a
        /// `SiteIcons` folder beside the session, named by its position in
        /// the list, for the client to copy out.
        func siteIcons(_ arguments: [String: Any]) async throws -> [String: Any] {
            let pages = (arguments["urls"] as? [String] ?? []).compactMap(URL.init(string:))
            let finder = BrowserSiteIconFinder()
            let profileID = UUID()
            let reports = await withTaskGroup(of: (Int, HarnessSiteIconReport).self) { group in
                for (index, page) in pages.enumerated() {
                    group.addTask {
                        async let finding = finder.icon(for: page, profileID: profileID)
                        async let defaultIconSide = Self.defaultIconSide(for: page)
                        return (
                            index,
                            HarnessSiteIconReport(
                                page: page.absoluteString, defaultIconSide: await defaultIconSide,
                                finding: await finding)
                        )
                    }
                }
                var reports: [(Int, HarnessSiteIconReport)] = []
                for await report in group { reports.append(report) }
                return reports.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let folder = directory.appendingPathComponent("SiteIcons", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var rows: [[String: Any]] = []
            for (index, report) in reports.enumerated() {
                var row: [String: Any] = ["page": report.page, "defaultIcon": report.defaultIconSide ?? 0]
                if let finding = report.finding {
                    let file = folder.appendingPathComponent("icon-\(index).icon")
                    try finding.data.write(to: file)
                    row["found"] = [
                        "kind": finding.relation.name, "url": finding.iconURL.absoluteString,
                        "width": finding.image.width, "height": finding.image.height, "file": file.path,
                    ]
                }
                rows.append(row)
            }
            return ["pages": rows]
        }

        /// The side of the image the page's `/favicon.ico` holds, as the
        /// fallback alone fetched and drew it, or nil when it gave none.
        nonisolated private static func defaultIconSide(for page: URL) async -> Int? {
            guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return nil }
            components.user = nil
            components.password = nil
            components.path = "/favicon.ico"
            components.query = nil
            components.fragment = nil
            guard let iconURL = components.url,
                let data = await BrowserFaviconFallbackLoader.download(iconURL),
                let image = BrowserFaviconImageDecoder.decodeSynchronously(data, maximumPixelSize: 512)
            else { return nil }
            return min(image.width, image.height)
        }
    }

#endif
