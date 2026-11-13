import Foundation

/// Where Back to Tab takes the person from a player: the window to show the
/// playing tab in, brought forward when it is not the one they are in, and
/// the tab's Space, unlocked first when it is locked. A tab under closed
/// folders shows on their way, as a shown tab always does, so the folders
/// stay as the person left them; a tab in a Split View shows with its split.
struct BrowserMediaReturnRoute: Equatable, Sendable {
    /// A browser window as Back to Tab weighs it.
    struct Window: Equatable, Sendable {
        let id: UUID
        /// Whether the window's workspace holds the tab at all; a torn-off
        /// tab's window holds only its own.
        let holdsTab: Bool
        /// Whether the window shows the tab now, where the video plays.
        let presentsTab: Bool
        /// Whether the window shows the tab's Space now.
        let showsSpace: Bool
    }

    let windowID: UUID
    let spaceID: UUID
    let tabID: UUID
    /// Whether the route brings another window forward, which only a person's
    /// own click asks for.
    let bringsWindowForward: Bool
    let unlocksSpace: Bool

    /// The route to `owner`'s tab from the window `sourceWindowID`, or nil
    /// when no open window holds the tab. A window that shows the tab wins,
    /// then the one the person is in, then one that shows the tab's Space,
    /// then the first that holds it.
    static func resolve(
        owner: BrowserTabRuntimeAssignment,
        fromWindow sourceWindowID: UUID?,
        windows: [Window],
        isSpaceLocked: Bool
    ) -> BrowserMediaReturnRoute? {
        let holding = windows.filter(\.holdsTab)
        guard
            let target = holding.first(where: \.presentsTab)
                ?? holding.first(where: { $0.id == sourceWindowID })
                ?? holding.first(where: \.showsSpace)
                ?? holding.first
        else { return nil }
        return BrowserMediaReturnRoute(
            windowID: target.id,
            spaceID: owner.spaceID,
            tabID: owner.tabID,
            bringsWindowForward: target.id != sourceWindowID,
            unlocksSpace: isSpaceLocked
        )
    }

    /// The session Back to Playing Tab goes to: the newest that plays, else
    /// the newest at all.
    static func target(in sessions: [BrowserMediaSessionSnapshot]) -> BrowserMediaSessionSnapshot? {
        sessions.filter { $0.playbackState == .playing }.max { $0.orderingOrdinal < $1.orderingOrdinal }
            ?? sessions.max { $0.orderingOrdinal < $1.orderingOrdinal }
    }
}
