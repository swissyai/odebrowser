import Foundation

/// What the Boost script in a page's main document said, read once from the
/// message's body: the document is ready for its CSS, the person hid an
/// element, or the person stopped hiding elements in the page.
struct BrowserBoostPageMessage: Equatable, Sendable {
    // MARK: - Types

    /// What the message reports, with the wire spelling of each kind and
    /// what the page's Boost session does on hearing it.
    struct Kind: Hashable, Sendable {
        static let ready = Kind(name: "ready", carriesSelector: false) { message, session in
            session.documentReady(site: message.site)
        }
        static let hid = Kind(name: "zapped", carriesSelector: true) { message, session in
            session.documentHid(message.selector ?? "", on: message.site)
        }
        static let stoppedHiding = Kind(name: "zapEnded", carriesSelector: false) { _, session in
            session.documentStoppedHiding()
        }
        static let all: [Kind] = [ready, hid, stoppedHiding]

        let name: String
        /// Whether a message of this kind names the element it hid.
        let carriesSelector: Bool
        fileprivate let perform: @MainActor @Sendable (BrowserBoostPageMessage, BrowserBoostSession) -> Void

        static func named(_ name: String) -> Kind? { all.first { $0.name == name } }

        static func == (lhs: Kind, rhs: Kind) -> Bool { lhs.name == rhs.name }

        func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    // MARK: - Variables

    let kind: Kind
    /// The site of the document that posted the message.
    let site: String
    /// The CSS selector of the element the person hid, for `hid`.
    let selector: String?

    // MARK: - Initializers

    /// The message `body` holds, or nil for one this build does not read or
    /// whose values are out of bounds.
    init?(body: Any) {
        guard let object = body as? [String: Any],
            (object["version"] as? Int) == BrowserBoostContentBridge.messageVersion,
            let kind = (object["kind"] as? String).flatMap(Kind.named),
            let site = object["site"] as? String, site.count <= SiteBoost.maximumSiteLength
        else { return nil }
        let selector = object["selector"] as? String
        if kind.carriesSelector {
            guard let selector, !selector.isEmpty, selector.count <= SiteBoost.maximumSelectorLength else { return nil }
        }
        self.kind = kind
        self.site = site
        self.selector = kind.carriesSelector ? selector : nil
    }

    // MARK: - Actions - Delivery

    /// Tells `session` what the document said.
    @MainActor
    func apply(to session: BrowserBoostSession) {
        kind.perform(self, session)
    }
}
