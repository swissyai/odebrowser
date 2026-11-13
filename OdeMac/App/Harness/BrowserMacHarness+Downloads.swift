#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import WebKit

    /// The harness's download commands: point the shown Space's downloads at
    /// a folder, start a download in the shown page as following a link does,
    /// wait for the shown Space's downloads and report them, cancel the ones
    /// still running, report, hide and clear what the sidebar shows of them,
    /// and show the downloads list to snapshot.
    extension BrowserMacHarness {
        // MARK: - Actions - Downloads

        /// Saves the shown Space's downloads into the folder at `path`, as
        /// choosing it in the Space's settings does.
        func setDownloadFolder(_ path: String) throws -> [String: Any] {
            guard path.hasPrefix("/") else { throw Failure(description: "setDownloadFolder needs an absolute path") }
            guard let space = try context().browser.shownSpace else { throw Failure(description: "No Space is shown") }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try BrowserPlatformDownloadPreferences.shared.rememberDirectory(folder, for: space.id)
            return ["spaceID": space.id.uuidString, "folder": folder.path]
        }

        /// Downloads `address` from the shown page, as the person following a
        /// download link there does. With `x` and `y`, in points from the
        /// page's top left, the file leaves from there for the sidebar.
        func startDownload(_ address: String, x: Double?, y: Double?) throws -> [String: Any] {
            guard let url = URL(string: address) else { throw Failure(description: "startDownload needs a URL") }
            guard let page = try context().pages.activePage, let webView = page.webKitAdapter?.webView else {
                throw Failure(description: "The shown tab has no WebKit page")
            }
            let source = feedbackSource(in: webView, x: x, y: y)
            webView.startDownload(using: URLRequest(url: url)) { [weak page, weak webView] download in
                guard let page, let webView else { return download.cancel { _ in } }
                page.startDownload(download, in: webView, isUserInitiated: true, feedbackSource: source)
            }
            return ["url": url.absoluteString]
        }

        /// Waits up to `timeout` seconds until the shown Space has `count`
        /// downloads in `phase`, or in any phase without one, and reports each
        /// of the Space's downloads, newest first.
        func downloads(count: Int, phase: String?, timeout: Double) async throws -> [String: Any] {
            let context = try context()
            func shown() -> [DownloadState] {
                guard let profileID = context.browser.shownSpace?.profileID else { return [] }
                return context.pages.downloadCenter.items(for: profileID)
            }
            let deadline = Date.now.addingTimeInterval(timeout)
            while shown().filter({ phase == nil || $0.phase.name == phase }).count < count, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return ["downloads": shown().map(describe)]
        }

        /// Cancels every download of the shown Space that is still running, as
        /// its Cancel button does, so a quit leaves no transfer behind.
        func cancelDownloads() throws -> [String: Any] {
            let context = try context()
            guard let profileID = context.browser.shownSpace?.profileID else { return ["canceled": 0] }
            let live = context.pages.downloadCenter.items(for: profileID).filter(\.phase.isLive)
            for item in live { context.pages.downloadCenter.cancel(item.id) }
            return ["canceled": live.count]
        }

        /// What the foot of the sidebar shows of the shown Space's downloads:
        /// the files in its rows, how many more the list holds, and whether it
        /// shows at all.
        func recentDownloads() throws -> [String: Any] {
            let context = try context()
            let center = context.pages.downloadCenter
            let items = context.browser.shownSpace.map { center.items(for: $0.profileID) } ?? []
            let recent = BrowserRecentDownloads(items: items, endTime: center.endTime(of:), now: .now)
            return [
                "shown": recent.shown.map(\.filename), "more": recent.moreCount,
                "visible": BrowserRecentDownloads.isShown(recent, besides: context.chrome.utilityPresentation.surface),
            ]
        }

        /// Marks the shown Space's downloads seen, as Hide at the foot of the
        /// sidebar does.
        func hideRecentDownloads() throws -> [String: Any] {
            let context = try context()
            guard let profileID = context.browser.shownSpace?.profileID else { return ["seen": 0] }
            return ["seen": context.pages.downloadCenter.acknowledgeItems(for: profileID)]
        }

        /// Clears the shown Space's ended downloads through the sidebar's own
        /// action, as Clear Downloads in the list's filter menu does.
        func clearDownloads() throws -> [String: Any] {
            let context = try context()
            guard let application = shell.application, let space = context.browser.shownSpace else {
                throw Failure(description: "No Space is shown")
            }
            let coordinator = BrowserSidebarUtilityCoordinator(
                browser: context.browser, pages: context.pages, spaceAccess: application.spaceAccess)
            let before = context.pages.downloadCenter.items(for: space.profileID).count
            coordinator.actions.clearDownloads?(BrowserSpaceRuntimeAssignment(space: space))
            return ["cleared": before - context.pages.downloadCenter.items(for: space.profileID).count]
        }

        /// Shows the downloads list in the shown Space's sidebar, as the
        /// sidebar's list button does, or closes it.
        func showDownloads(_ on: Bool) throws -> [String: Any] {
            let presentation = try context().chrome.utilityPresentation
            if on { presentation.present(.downloads) } else { presentation.dismiss() }
            return ["surface": presentation.surface?.name ?? ""]
        }

        private func describe(_ item: DownloadState) -> [String: Any] {
            [
                "id": item.id.uuidString, "filename": item.filename, "phase": item.phase.name,
                "progress": item.progress, "path": item.destinationURL?.path ?? "",
                "acknowledged": item.isAcknowledged, "bytes": item.telemetry.bytesReceived,
            ]
        }

        /// Where a download from `webView` leaves from: `x`, `y` in the page,
        /// measured from the window content's top left.
        private func feedbackSource(in webView: WKWebView, x: Double?, y: Double?) -> BrowserDownloadFeedbackSource? {
            guard let x, let y, let window = webView.window, let content = window.contentView else { return nil }
            let local = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
            let inContent = content.convert(webView.convert(local, to: nil), from: nil)
            return BrowserDownloadFeedbackSource(
                pointInGlobal: CGPoint(
                    x: inContent.x, y: content.isFlipped ? inContent.y : content.bounds.height - inContent.y),
                windowIdentifier: ObjectIdentifier(window))
        }
    }

#endif
