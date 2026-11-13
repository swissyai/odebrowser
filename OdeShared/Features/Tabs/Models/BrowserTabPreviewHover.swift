import Foundation
import Observation

/// Which pinned or saved tab's preview card a window shows. The card comes
/// up once the pointer rests on the tab's row or tile, moves at once from
/// one tab to the next while it shows, stays while the pointer is on the
/// card, and goes a moment after the pointer leaves both. It can also be
/// shown without the pointer, as an accessibility action does.
@MainActor
@Observable
final class BrowserTabPreviewHover {
    // MARK: - Types

    /// A tab whose card shows, and where its row or tile is in the window.
    struct Target: Equatable {
        let assignment: BrowserTabRuntimeAssignment
        let frame: CGRect
    }

    // MARK: - Static Variables

    /// How long the pointer rests on a tab before its card shows.
    static let showDelay: Duration = .milliseconds(450)
    /// How long the card stays after the pointer leaves it and its tab.
    static let hideDelay: Duration = .milliseconds(250)

    // MARK: - Variables

    /// The tab whose card shows now.
    private(set) var shown: Target? {
        didSet { if shown == nil { cardFrame = nil } }
    }
    /// Where the card is in the window while it shows.
    @ObservationIgnored private(set) var cardFrame: CGRect?
    /// Where the rows and tiles of tabs with a preview are in the window.
    @ObservationIgnored private var frames: [BrowserTabRuntimeAssignment: CGRect] = [:]
    @ObservationIgnored private var hovered: BrowserTabRuntimeAssignment?
    @ObservationIgnored private var isCardHovered = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Hears that a tab's card is about to show, so a preview that is no
    /// longer fresh is read again.
    @ObservationIgnored var willShow: @MainActor (BrowserTabRuntimeAssignment) -> Void = { _ in }

    // MARK: - Actions - Tabs

    /// The row or tile of the tab `assignment` names is at `frame` in the
    /// window, or gone for nil.
    func place(_ assignment: BrowserTabRuntimeAssignment, at frame: CGRect?) {
        frames[assignment] = frame
        guard shown?.assignment == assignment else { return }
        if let frame {
            if shown?.frame != frame { shown = Target(assignment: assignment, frame: frame) }
        } else {
            dismiss()
        }
    }

    /// The pointer entered or left the row or tile of the tab `assignment`
    /// names.
    func pointer(isOver: Bool, on assignment: BrowserTabRuntimeAssignment) {
        if isOver {
            hovered = assignment
            if shown != nil {
                pending?.cancel()
                show(assignment)
            } else {
                schedule(after: Self.showDelay) { [weak self] in self?.show(assignment) }
            }
        } else if hovered == assignment {
            hovered = nil
            scheduleHiding()
        }
    }

    /// The card of the tab `assignment` names is at `frame` in the window;
    /// a card on its way out says nothing.
    func card(of assignment: BrowserTabRuntimeAssignment, isAt frame: CGRect) {
        guard shown?.assignment == assignment else { return }
        cardFrame = frame
    }

    /// The pointer entered or left the card.
    func card(isHovered: Bool) {
        isCardHovered = isHovered
        if isHovered { pending?.cancel() } else { scheduleHiding() }
    }

    /// Shows the card of the tab `assignment` names now, beside its row or
    /// tile.
    func show(_ assignment: BrowserTabRuntimeAssignment) {
        guard let frame = frames[assignment] else { return }
        willShow(assignment)
        shown = Target(assignment: assignment, frame: frame)
    }

    /// Takes the card down now.
    func dismiss() {
        pending?.cancel()
        hovered = nil
        isCardHovered = false
        shown = nil
    }

    private func scheduleHiding() {
        schedule(after: Self.hideDelay) { [weak self] in
            guard let self, hovered == nil, !isCardHovered else { return }
            shown = nil
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
