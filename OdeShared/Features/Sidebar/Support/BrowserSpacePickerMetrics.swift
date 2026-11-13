import CoreGraphics

/// The drawn geometry of one Space in the switcher, resolved once per shell
/// rather than spelled out by each segment.
///
/// A segment is an icon with a lock badge on its corner, and both are sized by
/// how close the reader's aim can get: a pointer lands on a 24pt icon, while
/// a finger needs a larger one with clearance around it before the
/// neighbouring Space becomes a misfire.
struct BrowserSpacePickerMetrics: Equatable, Sendable {
    // MARK: - Static Variables

    /// A pointer shell: a small icon that fills the compact picker's segment
    /// on its own.
    static let pointer = BrowserSpacePickerMetrics(
        iconSize: 24,
        lockSize: 6,
        iconPadding: 0
    )

    /// A touch shell: a larger icon with clearance around it, drawn in the
    /// square a finger aims at.
    static let touch = BrowserSpacePickerMetrics(
        iconSize: 30,
        lockSize: 7,
        iconPadding: 4
    )

    // MARK: - Variables

    /// The square the Space's icon is drawn into.
    let iconSize: CGFloat

    /// The badge drawn on a private Space's icon. It travels with the icon
    /// rather than being fixed, so the two scale together.
    let lockSize: CGFloat

    /// The clearance around the icon inside its segment.
    let iconPadding: CGFloat

    // MARK: - Actions - Sizing

    /// These metrics with the icon, its badge and its clearance drawn `scale`
    /// times their usual size, in whole points. The icon stays an even number
    /// of points, as its segment is, so it centres on a whole point.
    func scaled(by scale: CGFloat) -> BrowserSpacePickerMetrics {
        BrowserSpacePickerMetrics(
            iconSize: 2 * (iconSize * scale / 2).rounded(),
            lockSize: (lockSize * scale).rounded(),
            iconPadding: (iconPadding * scale).rounded()
        )
    }
}
