import Foundation
import Observation

/// One page's Boosts: what its Space keeps, the one the person edits, and the
/// Boost script in the page's documents, through whichever engine shows it.
/// A page whose engine runs no Boost script has none to offer.
@MainActor
@Observable
final class BrowserBoostSession {
    // MARK: - Static Variables

    /// How long an edit waits for the next before the Space keeps it.
    static let saveDelay: Duration = .milliseconds(400)
    /// Ode blue, which outlines the element the pointer would hide.
    static let outlineColor = "#3050f0"

    // MARK: - Variables

    /// The Boosts the page's Space keeps.
    private(set) var boosts: SpaceBoosts?
    /// The Boost the person is editing, which the page shows in place of the
    /// one its site keeps until the Space keeps it too.
    private(set) var draft: SiteBoost?
    /// The person is editing the site's Boost.
    private(set) var isEditing = false
    /// The person is picking elements in the page to hide.
    private(set) var isHiding = false
    /// The site of the page's main document, as its Boost script last said.
    private(set) var documentSite: String?
    /// The CSS Focus adds to each site's pages, after the Space's Boost.
    private(set) var focusStyles: [String: String] = [:]

    /// The address the page shows, whose site a Boost applies to.
    @ObservationIgnored var siteURL: @MainActor () -> URL? = { nil }
    /// Keeps a Boost in the page's Space.
    @ObservationIgnored var save: @MainActor (SiteBoost) -> Void = { _ in }
    /// Forgets the page's Space's Boost for a site.
    @ObservationIgnored var remove: @MainActor (String) -> Void = { _ in }

    @ObservationIgnored private var document: (any BrowserBoostDocument)?
    @ObservationIgnored private var preparedStyles: [String: String] = [:]
    @ObservationIgnored private var preparedKeepsScript = false
    /// The CSS the page's main document wears now, as far as this session put it there.
    @ObservationIgnored private var appliedCSS = ""
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// The site the page shows, or nil for a page without one.
    var site: String? { BrowserSite.of(siteURL()) }
    /// Whether the person can boost the page: its engine runs the Boost
    /// script and it shows a site.
    var isAvailable: Bool { document != nil && site != nil }
    /// The Boost the page's site keeps, on or off.
    var kept: SiteBoost? { site.flatMap { boosts?.boost(forSite: $0) } }
    /// The Boost the page shows: the one being edited, else the kept one.
    var shown: SiteBoost? {
        if let draft, draft.site == site { return draft }
        return kept
    }

    // MARK: - Actions - Engine

    /// Runs the page's Boosts through `document`, the page's engine's, or
    /// none for an engine that runs no Boost script.
    func attach(_ document: (any BrowserBoostDocument)?) {
        self.document?.close()
        self.document = document
        preparedStyles = [:]
        preparedKeepsScript = false
        appliedCSS = ""
        refresh()
    }

    /// Lets go of the page's engine, keeping what the person edits.
    func detach() {
        stopHiding()
        document?.close()
        document = nil
    }

    // MARK: - Actions - Following the Space

    /// Follows the Boosts the page's Space keeps now.
    func follow(_ boosts: SpaceBoosts?) {
        guard boosts != self.boosts else { return }
        self.boosts = boosts
        refresh()
    }

    /// Follows what Focus hides on each site now.
    func followFocus(_ styles: [String: String]) {
        guard styles != focusStyles else { return }
        focusStyles = styles
        refresh()
    }

    // MARK: - Actions - Editing

    /// Starts editing the page's site's Boost, or a new one that changes
    /// nothing yet.
    func beginEditing() {
        guard let site, document != nil else { return }
        if draft?.site != site { draft = boosts?.boost(forSite: site) ?? SiteBoost(blankFor: site) }
        isEditing = true
        refresh()
    }

    /// Stops editing, keeping what the person changed.
    func endEditing() {
        stopHiding()
        flush()
        isEditing = false
        draft = nil
        refresh()
    }

    /// Changes the Boost being edited, shows it on the page at once and has
    /// the Space keep it once the person pauses.
    func change(_ edit: (inout SiteBoost) -> Void) {
        guard var boost = draft else { return }
        edit(&boost)
        guard boost != draft else { return }
        draft = boost
        refresh()
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Turns the site's Boost on or off, now.
    func setEnabled(_ isEnabled: Bool) {
        if draft != nil {
            change { $0.isEnabled = isEnabled }
            flush()
        } else if var boost = kept {
            boost.isEnabled = isEnabled
            save(boost)
        }
    }

    /// Shows an element the person hid again.
    func showHidden(_ selector: String) {
        change { $0.hiddenSelectors.removeAll { $0 == selector } }
        flush()
    }

    /// Forgets the site's Boost and stops editing it.
    func removeBoost() {
        guard let site = draft?.site ?? site else { return }
        stopHiding()
        pendingSave?.cancel()
        pendingSave = nil
        draft = nil
        isEditing = false
        remove(site)
        refresh()
    }

    /// Has the Space keep the Boost being edited now, unless it is a new one
    /// that changes nothing.
    private func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let draft, draft.changesPages || boosts?.boost(forSite: draft.site) != nil,
            draft != boosts?.boost(forSite: draft.site)
        else { return }
        save(draft)
    }

    // MARK: - Actions - Hiding elements

    /// Starts or stops picking elements in the page to hide.
    func setHiding(_ isHiding: Bool) {
        guard isHiding != self.isHiding, !isHiding || (isEditing && document != nil) else { return }
        self.isHiding = isHiding
        run(BrowserBoostContentBridge.zapBody, ["on": isHiding, "color": Self.outlineColor])
    }

    private func stopHiding() {
        setHiding(false)
    }

    // MARK: - Actions - Documents

    /// The page's main document of `site` is ready for its CSS.
    func documentReady(site: String) {
        if documentSite != site, isEditing, let draft, draft.site != site {
            flush()
            self.draft = boosts?.boost(forSite: site) ?? SiteBoost(blankFor: site)
        }
        documentSite = site
        let css = styles[site] ?? ""
        if !css.isEmpty { run(BrowserBoostContentBridge.applyBody, ["site": site, "css": css]) }
        appliedCSS = css
        if isHiding { run(BrowserBoostContentBridge.zapBody, ["on": true, "color": Self.outlineColor]) }
    }

    /// The person hid the element `selector` names in the page's main
    /// document of `site`.
    func documentHid(_ selector: String, on site: String) {
        guard isHiding, draft?.site == site else { return }
        change { boost in
            if !boost.hiddenSelectors.contains(selector), boost.hiddenSelectors.count < SiteBoost.maximumHiddenSelectors
            {
                boost.hiddenSelectors.append(selector)
            }
        }
        flush()
    }

    /// The person stopped picking elements from inside the page.
    func documentStoppedHiding() {
        isHiding = false
    }

    // MARK: - Actions - Styles

    /// The CSS each site's pages wear: what the Space keeps, with the Boost
    /// being edited in place of its site's, then what Focus hides there.
    private var styles: [String: String] {
        var styles = boosts?.stylesheets ?? [:]
        if let draft {
            let css = draft.isEnabled ? draft.stylesheet : ""
            styles[draft.site] = css.isEmpty ? nil : css
        }
        for (site, css) in focusStyles {
            styles[site] = [styles[site], css].compactMap { $0 }.joined(separator: "\n")
        }
        return styles
    }

    /// Prepares the page's later documents for the CSS each site wears and
    /// puts its site's on the document it shows now.
    private func refresh() {
        guard let document else { return }
        let styles = styles
        if styles != preparedStyles || isEditing != preparedKeepsScript {
            document.prepare(styles: styles, keepsScript: isEditing)
            preparedStyles = styles
            preparedKeepsScript = isEditing
        }
        guard let site else { return }
        let css = styles[site] ?? ""
        guard css != appliedCSS else { return }
        appliedCSS = css
        run(BrowserBoostContentBridge.applyBody, ["site": site, "css": css])
    }

    private func run(_ body: String, _ arguments: [String: Any]) {
        guard let document else { return }
        Task { @MainActor in await document.run(body, arguments: arguments) }
    }

    /// Hears what a document's Boost script said.
    func receive(_ message: BrowserBoostPageMessage) {
        message.apply(to: self)
    }
}
