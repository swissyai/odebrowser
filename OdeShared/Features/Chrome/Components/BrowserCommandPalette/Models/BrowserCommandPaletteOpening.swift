import SwiftUI

/// What a platform's palette can do with an address it opens: open it in
/// place of what the source tab shows, in a new tab behind or in front of it,
/// beside it in Split View, or in a Quick Window. Each answers whether it
/// opened the address.
@MainActor
protocol BrowserCommandPaletteOpener {
    func openHere(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool
    func openTab(_ url: URL, from source: BrowserTabRuntimeAssignment, selecting: Bool) -> Bool
    func openInSplit(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool
    func openInQuickWindow(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool
}

/// Where activating a palette row that opens an address opens it, which the
/// modifier keys a person holds choose: here, in a new tab behind or in front
/// of the current one, beside it in Split View, or in a Quick Window; or, for
/// a search, its first result here instead of the results. Each names the
/// keys that choose it, what the selected row says and wears while they are
/// held, what the selected row says Shift-Return does when it does this, and
/// how it opens an address through a platform's opener.
struct BrowserCommandPaletteOpening: Hashable, Sendable {
    // MARK: - Static Variables

    static let here = BrowserCommandPaletteOpening(
        name: "here", modifiers: [], title: nil, symbol: "arrow.turn.down.left"
    ) { opener, url, source in opener.openHere(url, from: source) }
    static let backgroundTab = BrowserCommandPaletteOpening(
        name: "backgroundTab", modifiers: [.command], title: "Open in Background", symbol: "square.on.square"
    ) { opener, url, source in opener.openTab(url, from: source, selecting: false) }
    static let newTab = BrowserCommandPaletteOpening(
        name: "newTab", modifiers: [.command, .shift], title: "Open in New Tab", symbol: "plus.square.on.square"
    ) { opener, url, source in opener.openTab(url, from: source, selecting: true) }
    static let splitView = BrowserCommandPaletteOpening(
        name: "splitView", modifiers: [.shift], title: "Open in Split View", hint: "Split View",
        symbol: "rectangle.split.2x1"
    ) { opener, url, source in opener.openInSplit(url, from: source) }
    static let quickWindow = BrowserCommandPaletteOpening(
        name: "quickWindow", modifiers: [.option], title: "Open in Quick Window", symbol: "macwindow"
    ) { opener, url, source in opener.openInQuickWindow(url, from: source) }
    /// A search's first result, opened where Return opens the search. The
    /// palette chooses it for Shift on a row that has one, in place of Split
    /// View, so it is never among a platform's openings.
    static let topResult = BrowserCommandPaletteOpening(
        name: "topResult", modifiers: [.shift], title: "Open Top Result", hint: "Top Result", symbol: "arrow.up.forward"
    ) { opener, url, source in opener.openHere(url, from: source) }

    static let all: [BrowserCommandPaletteOpening] = [here, backgroundTab, newTab, splitView, quickWindow]

    // MARK: - Variables

    let name: String
    /// The modifier keys that choose this opening with Return.
    let modifiers: EventModifiers
    /// What the selected row says while the keys are held, or nil to keep
    /// the row's own words.
    let title: LocalizedStringResource?
    /// What the selected row says Shift-Return does while no keys are held,
    /// when Shift-Return does this, or nil.
    let hint: LocalizedStringResource?
    /// The SF Symbol the selected row wears at its end.
    let symbol: String
    /// Opens an address from a source tab through a platform's opener.
    private let open: @MainActor @Sendable (any BrowserCommandPaletteOpener, URL, BrowserTabRuntimeAssignment) -> Bool

    // MARK: - Initializers

    private init(
        name: String, modifiers: EventModifiers, title: LocalizedStringResource?, hint: LocalizedStringResource? = nil,
        symbol: String,
        open: @escaping @MainActor @Sendable (any BrowserCommandPaletteOpener, URL, BrowserTabRuntimeAssignment) -> Bool
    ) {
        self.name = name
        self.modifiers = modifiers
        self.title = title
        self.hint = hint
        self.symbol = symbol
        self.open = open
    }

    // MARK: - Actions - Lookup

    /// The opening `held` chooses among `available`, or `here` for keys that
    /// choose none of them.
    static func held(_ held: EventModifiers, among available: [BrowserCommandPaletteOpening])
        -> BrowserCommandPaletteOpening
    {
        let keys = held.intersection([.command, .shift, .option])
        return available.first { $0.modifiers == keys } ?? .here
    }

    // MARK: - Actions - Opening

    /// Opens `url` from `source` this way through `opener`.
    @MainActor
    func open(_ url: URL, from source: BrowserTabRuntimeAssignment, with opener: any BrowserCommandPaletteOpener)
        -> Bool
    {
        open(opener, url, source)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
