#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import SwiftUI

    /// The harness's commands for Ode's secondary surfaces: a Space's
    /// archive, history and downloads lists, the page each kind of failed
    /// navigation shows, and a site's permission question, each shown where
    /// `snapshotWindow` can draw it.
    extension BrowserMacHarness {
        // MARK: - Actions - Utility lists

        /// Shows the shown Space's `name` list (archive, history or
        /// downloads) in the sidebar, as its buttons do, or closes the list
        /// shown when `name` is nil.
        func showUtility(_ name: String?) throws -> [String: Any] {
            let chrome = try context().chrome
            guard let name else {
                chrome.utilityPresentation.dismiss()
                return [:]
            }
            guard let surface = BrowserUtilitySurface.named(name) else {
                throw Failure(description: "No list is named \(name)")
            }
            chrome.presentUtility(surface)
            return ["surface": surface.name, "switcherExpanded": chrome.utilityPresentation.isSwitcherExpanded]
        }

        // MARK: - Actions - Failed navigations

        /// Draws the page a navigation that failed with the error `name`
        /// shows, on the shown Space's look, in a window titled "Navigation
        /// failure" of the size asked for.
        func showNavigationFailure(_ arguments: [String: Any]) throws -> [String: Any] {
            let name = arguments["error"] as? String
            guard let error = NavigationError.named(name) else {
                throw Failure(description: "No navigation error is named \(name ?? "")")
            }
            let address = arguments["url"] as? String ?? "https://example.com/"
            let failure = PageFailure(
                error: error, url: address, replacedDocument: true, domain: NSURLErrorDomain, code: 0)
            let width = CGFloat(arguments["width"] as? Double ?? 960)
            let height = CGFloat(arguments["height"] as? Double ?? 720)
            let layout: BrowserNavigationFailureLayout =
                arguments["layout"] as? String == "compact" ? .compact : .regular
            return show(
                BrowserNavigationFailureView(
                    failure: failure, layout: layout,
                    canGoBack: arguments["canGoBack"] as? Bool ?? true,
                    canProceed: error == .secureConnectionFailed, retry: {}, goBack: {}, proceed: {}
                ),
                titled: "Navigation failure", width: width, height: height, padding: 0)
        }

        // MARK: - Actions - Reports

        /// Stages one synthetic report in this harness's isolated store. It
        /// has no uploader, page data, or dependency on system crash records.
        func showCrashNotice() throws -> [String: Any] {
            guard let reports = shell.application?.crashReports, !reports.canSend else {
                throw Failure(description: "Report fixtures require a local-only isolated store")
            }
            reports.sending = .ask
            let report = BrowserCrashReport(
                id: "harness-\(UUID().uuidString)", kind: .crash, occurredAt: .now,
                build: "899", summary: "Synthetic report", details: "No system crash record was read.")
            reports.collect([report])
            return ["reportID": report.id, "unnoticed": reports.unnoticed.count, "canSend": reports.canSend]
        }

        /// Answers the report notice as Review does, without opening the
        /// list, so what it covers can be drawn. The answer is kept in the
        /// isolated session's own reports folder.
        func dismissReportNotice() throws -> [String: Any] {
            guard let reports = shell.application?.crashReports else {
                throw Failure(description: "The browser is not running")
            }
            let asked = reports.unnoticed
            reports.reviewNotice(about: asked)
            return ["answered": asked.count]
        }

        // MARK: - Actions - Permission questions

        /// Draws the question a site asks before using `permission`, as the
        /// site's address button shows it, in a window titled "Permission".
        func showPermissionPrompt(_ arguments: [String: Any]) throws -> [String: Any] {
            let name = arguments["permission"] as? String ?? "camera"
            guard let permission = SitePermission.all.first(where: { $0.name == name }) else {
                throw Failure(description: "No permission is named \(name)")
            }
            guard let url = URL(string: arguments["site"] as? String ?? "https://example.com"),
                let origin = SiteOrigin(url: url),
                let topLevelURL = URL(string: arguments["topLevelSite"] as? String ?? url.absoluteString),
                let topLevelOrigin = SiteOrigin(url: topLevelURL)
            else { throw Failure(description: "The site has no origin") }
            let request = BrowserPagePermissionController.Request(
                permission: permission, origin: origin, topLevelOrigin: topLevelOrigin,
                spaceName: try context().browser.shownSpace?.settings.name ?? "Personal")
            return show(
                BrowserPagePermissionPrompt(request: request, controller: BrowserPagePermissionController()),
                titled: "Permission", width: 280 + 2 * OdeSpacing.medium)
        }
    }

#endif
