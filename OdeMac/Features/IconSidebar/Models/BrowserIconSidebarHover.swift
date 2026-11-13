import CoreGraphics
import Foundation
import Observation

/// The title the sidebar as icons shows beside the icon the pointer rests
/// on, at once rather than after a tooltip's wait.
@MainActor
@Observable
final class BrowserIconSidebarHover {
    // MARK: - Types

    struct Target: Equatable {
        let title: String
        /// The icon's frame in the window, top down.
        let frame: CGRect
    }

    // MARK: - Variables

    private(set) var shown: Target?
    /// Where each tab's icon is, so its title can be shown without a pointer,
    /// as the harness does.
    @ObservationIgnored private var frames: [UUID: CGRect] = [:]

    // MARK: - Actions - Hover

    /// Notes where the icon of the tab `tabID` is.
    func place(_ tabID: UUID, at frame: CGRect) {
        frames[tabID] = frame
    }

    /// Shows `title` beside the icon of the tab `tabID`, and answers whether
    /// that icon is on screen.
    @discardableResult
    func show(_ title: String, of tabID: UUID) -> Bool {
        guard let frame = frames[tabID] else { return false }
        show(title, at: frame)
        return true
    }

    /// Shows `title` beside the icon at `frame`.
    func show(_ title: String, at frame: CGRect) {
        let target = Target(title: title, frame: frame)
        if shown != target { shown = target }
    }

    /// Takes the title away once the pointer leaves the icon at `frame`,
    /// unless it has already moved on to another icon.
    func leave(_ frame: CGRect) {
        if shown?.frame == frame { shown = nil }
    }

    func dismiss() {
        shown = nil
    }
}
