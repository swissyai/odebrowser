#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import Foundation

    /// The harness's preview commands: have a page served on this Mac stand
    /// in for a site with previews, read the previews and report them, show a
    /// pinned or saved tab's card as resting the pointer on it would, and open
    /// one of its items as choosing it would.
    extension BrowserMacHarness {
        // MARK: - Actions - Tab previews

        /// Has pages at `origin`, such as `http://127.0.0.1:8080`, stand in for
        /// the site `site` names, or for none without one.
        func standInTabPreviewSite(origin: String, site: String?) throws -> [String: Any] {
            let previews = try context().pages.runtimeStore.tabPreviews
            previews.standIns[origin] = BrowserTabPreviewSite.named(site)
            previews.refresh()
            return ["origin": origin, "site": site ?? ""]
        }

        /// Reads the previews that are due, waits up to `timeout` seconds
        /// until `count` tabs have one, and reports each: its tab, count,
        /// items and whether its page was signed out.
        func tabPreviews(count: Int, timeout: Double) async throws -> [String: Any] {
            let previews = try context().pages.runtimeStore.tabPreviews
            previews.refresh()
            let deadline = Date.now.addingTimeInterval(timeout)
            while previews.previews.count < count, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return [
                "running": previews.isRunning,
                "previews": previews.previews.map { tabID, preview -> [String: Any] in
                    [
                        "tabID": tabID.uuidString, "unread": preview.unreadCount ?? -1,
                        "items": preview.items.map(\.title), "signedOut": preview.isSignedOut,
                        "account": preview.account ?? "", "badge": preview.badge(at: .now)?.text ?? "",
                    ]
                },
            ]
        }

        /// Shows the card of the pinned or saved tab in the shown Space whose
        /// address or title holds `text`.
        func showTabPreview(matching text: String) throws -> [String: Any] {
            let context = try context()
            let assignment = try previewedTab(matching: text, in: context)
            context.chrome.tabPreviewHover.show(assignment)
            guard context.chrome.tabPreviewHover.shown?.assignment == assignment else {
                throw Failure(description: "The tab's row or tile is not on screen")
            }
            return ["tabID": assignment.tabID.uuidString]
        }

        func hideTabPreview() throws -> [String: Any] {
            try context().chrome.tabPreviewHover.dismiss()
            return [:]
        }

        /// Opens item `index` of the card of the tab whose address or title
        /// holds `text`, as choosing it does, and reports where it opens and,
        /// once it got there or after 3 s, where the tab's page is.
        func openTabPreviewItem(matching text: String, index: Int) async throws -> [String: Any] {
            let context = try context()
            let assignment = try previewedTab(matching: text, in: context)
            guard let preview = context.pages.tabPreview(matching: assignment) else {
                throw Failure(description: "The tab has no preview")
            }
            let items = preview.current(at: .now)
            let item = items.indices.contains(index) ? items[index] : nil
            context.chrome.tabPreviewHover.dismiss()
            context.pages.openTabPreviewItem(item, in: assignment)
            let link = item?.link?.absoluteString ?? ""
            var pageURL = ""
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                pageURL = context.pages.residentPage(matching: assignment)?.pageEngine.currentURL?.absoluteString ?? ""
                if pageURL == link { break }
            }
            return ["link": link, "pageURL": pageURL, "shownTab": context.browser.shownTab?.id == assignment.tabID]
        }

        private func previewedTab(
            matching text: String, in context: BrowserMacWindowContext
        ) throws -> BrowserTabRuntimeAssignment {
            guard let space = context.browser.shownSpace,
                let tab = space.tabs.models.first(where: {
                    $0.placement.isDurable && (($0.url ?? "").contains(text) || $0.title.contains(text))
                })
            else { throw Failure(description: "No pinned or saved tab in the shown Space matches \(text)") }
            return BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        }
    }

#endif
