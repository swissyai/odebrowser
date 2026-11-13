import AppKit

/// What covers the page's view until its document draws: the colour its site
/// paints before a first load or while it wakes, and the page before while a
/// navigation its engine does not hold goes on; see
/// `BrowserPagePaintHold`.
extension BrowserPage {
    // MARK: - Actions - Covering

    /// What covers the page's view now: the hold's cover, unless the page
    /// shows a failure of its own instead.
    var shownPaintCover: BrowserPagePaintCover? {
        live.failure == nil && webContentFailureMessage == nil ? paintHold.cover : nil
    }

    /// The colour a page of `url`'s site is expected to paint: what it
    /// painted last, else the page colour of the person's appearance, so a
    /// dark Mac never shows a white frame for a site it has not seen.
    func expectedBackground(for url: URL?) -> CGColor {
        if let remembered = BrowserSiteBackgrounds.shared.background(for: url, in: profileID) {
            return CGColor(srgbRed: remembered.red, green: remembered.green, blue: remembered.blue, alpha: 1)
        }
        let appearance = nativeView.window?.effectiveAppearance ?? NSApp.effectiveAppearance
        var color = CGColor(gray: 1, alpha: 1)
        appearance.performAsCurrentDrawingAppearance { color = NSColor.controlBackgroundColor.cgColor }
        return color
    }

    /// Covers a page's first load with its site's remembered background.
    /// This includes a sleeping tab whose previous engine page was released.
    func coverFirstLoad(of tab: BrowserPageTab) {
        guard !hasCoveredFirstLoad, committedNavigationCount == 0, engineAdapter.reportsPaints else { return }
        hasCoveredFirstLoad = true
        let url = tab.url
        paintHold.hold(image: nil, color: expectedBackground(for: url))
    }

    /// A load began. An engine that drops the page before as the next
    /// document commits gets a picture of it taken now, to cover the page
    /// from that commit until the new document draws.
    func navigationStarted() {
        guard !engineAdapter.holdsNavigationsUntilPainted, engineAdapter.reportsPaints,
            committedNavigationCount > 0, nativeView.window != nil, !nativeView.bounds.isEmpty
        else { return }
        let from = live.documentURL
        let generation = navigationCoverGeneration &+ 1
        navigationCoverGeneration = generation
        navigationCover = nil
        captureViewport(width: nativeView.bounds.width) { [weak self] image in
            guard let self, self.navigationCoverGeneration == generation else { return }
            self.navigationCover = image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { ($0, from) }
        }
    }

    /// A document committed at `url`. A new document from another origin,
    /// on an engine that does not hold the page before, is covered with the
    /// picture taken as its load began.
    func navigationCommitted(to url: URL?, isLoading: Bool) {
        defer {
            navigationCoverGeneration &+= 1
            navigationCover = nil
        }
        guard isLoading, let (image, from) = navigationCover, Self.origin(of: from) != Self.origin(of: url) else {
            return
        }
        paintHold.hold(image: image, color: expectedBackground(for: url))
    }

    /// The page's document drew, with the background it painted: the cover
    /// goes, its site is remembered with that colour, and a tab switch to
    /// this page is over.
    func receivePaintMessage(_ body: Any) {
        guard let report = BrowserPagePaintBridge.report(body), report.url == live.documentURL else { return }
        if let background = report.background, corePage.keepsBrowsingRecords {
            BrowserSiteBackgrounds.shared.record(
                background, for: live.documentURL, in: profileID, isPrivate: isPrivateBrowsing)
        }
        paintHold.painted()
        BrowserTabSwitchClock.shared.drew(self)
    }

    private static func origin(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(url.port ?? -1)"
    }
}
