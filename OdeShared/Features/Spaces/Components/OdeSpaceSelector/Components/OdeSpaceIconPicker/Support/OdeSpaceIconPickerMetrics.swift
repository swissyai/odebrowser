import CoreGraphics

/// Shared measurements for the compact Space icon picker.
enum OdeSpaceIconPickerMetrics {
    static let segmentWidth: CGFloat = 40
    static let segmentHeight: CGFloat = 30
    static let cornerRadius: CGFloat = OdeRadius.compact
    static let trackPadding: CGFloat = 3
    static let trackFillOpacity = OdeOpacity.hover
    static let trackBorderOpacity = OdeOpacity.border
    /// The compact picker marks the current Space by its icon's color alone:
    /// no fill, no outline, no track and no dividers.
    static let selectionFillOpacity = 0.0
    static let selectionStroke: CGFloat = 1.5
    /// A group's outline: half the selection's fill, the selection's stroke,
    /// and the selection set inside it by the track's padding.
    static let groupOutlineFillOpacity = selectionFillOpacity / 2
    static let groupOutlineStroke: CGFloat = selectionStroke
    /// How far the selection's and a group's strokes move from the Space's
    /// colour toward the reading colour, so they hold against a backdrop of
    /// the same hue.
    static let strokeLift: CGFloat = 0.3
    static let groupSelectionInset: CGFloat = trackPadding
    static let overflowButtonWidth: CGFloat = 28
}

/// Styling changes with input size; selection, overflow and actions are shared.
struct OdeSpaceIconPickerStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = OdeSpaceIconPickerStyle(
        name: "compact",
        height: OdeSpaceIconPickerMetrics.segmentHeight + 2 * OdeSpaceIconPickerMetrics.trackPadding,
        trackPadding: OdeSpaceIconPickerMetrics.trackPadding,
        fixedCornerRadius: OdeSpaceIconPickerMetrics.cornerRadius,
        minimumSegmentWidth: OdeSpaceIconPickerMetrics.segmentWidth, smallestSegment: .zero,
        overflowButtonWidth: OdeSpaceIconPickerMetrics.overflowButtonWidth, fillsSegments: false,
        trackFillOpacity: 0, trackBorderOpacity: 0, tintsSelection: false,
        selectionFillOpacity: OdeSpaceIconPickerMetrics.selectionFillOpacity)
    static let touch = OdeSpaceIconPickerStyle(
        name: "touch", height: 48, trackPadding: OdeSpaceIconPickerMetrics.trackPadding, fixedCornerRadius: nil,
        minimumSegmentWidth: 52, smallestSegment: CGSize(width: 44, height: 42), overflowButtonWidth: 44,
        fillsSegments: true, trackFillOpacity: 0.08,
        trackBorderOpacity: 0, tintsSelection: false, selectionFillOpacity: 0.22)

    // MARK: - Variables

    let name: String
    private(set) var height: CGFloat

    /// The clearance between the track's edge and the segments inside it.
    private(set) var trackPadding: CGFloat

    /// The corner radius every part of the picker shares, or `nil` where each
    /// part is a capsule.
    private(set) var fixedCornerRadius: CGFloat?

    private(set) var minimumSegmentWidth: CGFloat

    /// The smallest a segment gets however small its emblem is drawn. Touch
    /// keeps its full height and the width a finger needs; a pointer's
    /// segments shrink with their emblems.
    let smallestSegment: CGSize

    let overflowButtonWidth: CGFloat

    /// Whether the segments widen to share the whole width the picker has.
    let fillsSegments: Bool

    let trackFillOpacity: Double
    let trackBorderOpacity: Double

    /// Whether the selected Space wears its own tint and outline, or a
    /// neutral fill.
    let tintsSelection: Bool

    let selectionFillOpacity: Double

    /// The height of one segment inside the track.
    var segmentHeight: CGFloat {
        height - 2 * trackPadding
    }

    // MARK: - Initializers

    private init(
        name: String, height: CGFloat, trackPadding: CGFloat, fixedCornerRadius: CGFloat?,
        minimumSegmentWidth: CGFloat, smallestSegment: CGSize, overflowButtonWidth: CGFloat, fillsSegments: Bool,
        trackFillOpacity: Double, trackBorderOpacity: Double, tintsSelection: Bool, selectionFillOpacity: Double
    ) {
        self.name = name
        self.height = height
        self.trackPadding = trackPadding
        self.fixedCornerRadius = fixedCornerRadius
        self.minimumSegmentWidth = minimumSegmentWidth
        self.smallestSegment = smallestSegment
        self.overflowButtonWidth = overflowButtonWidth
        self.fillsSegments = fillsSegments
        self.trackFillOpacity = trackFillOpacity
        self.trackBorderOpacity = trackBorderOpacity
        self.tintsSelection = tintsSelection
        self.selectionFillOpacity = selectionFillOpacity
    }

    // MARK: - Actions - Drawing

    /// The corner radius of a part of the picker `height` tall: the compact
    /// radius, or for touch half the height, so every part is a capsule.
    /// `OdeSpaceIconPickerShape` draws every part with it.
    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        fixedCornerRadius ?? height / 2
    }

    // MARK: - Actions - Sizing

    /// This style with segments sized for an emblem drawn `scale` times its
    /// usual size, down to `smallestSegment`.
    ///
    /// The track's padding and corners follow the segment's height, so a
    /// smaller track keeps the shape of the full-size one rather than rounding
    /// off. Segments come out an even number of points each way and the
    /// padding a whole one, so a track of any size, and the emblems centred in
    /// it, centre on the same point as the controls beside it.
    func scaled(by scale: CGFloat) -> OdeSpaceIconPickerStyle {
        let segmentHeight = max(smallestSegment.height, Self.evenPoints(self.segmentHeight * scale))
        let shape = segmentHeight / self.segmentHeight
        var style = self
        style.trackPadding = (trackPadding * shape).rounded()
        style.height = segmentHeight + 2 * style.trackPadding
        style.fixedCornerRadius = fixedCornerRadius.map { $0 * shape }
        style.minimumSegmentWidth = max(smallestSegment.width, Self.evenPoints(minimumSegmentWidth * scale))
        return style
    }

    /// `length` to the nearest even number of points.
    private static func evenPoints(_ length: CGFloat) -> CGFloat {
        2 * (length / 2).rounded()
    }

    /// How wide the track is with `spaceCount` Spaces side by side at their
    /// narrowest.
    func contentWidth(spaceCount: Int) -> CGFloat {
        guard spaceCount > 0 else { return 0 }
        return 2 * trackPadding + CGFloat(spaceCount) * minimumSegmentWidth
    }

    // MARK: - Actions - Identity

    static func == (lhs: OdeSpaceIconPickerStyle, rhs: OdeSpaceIconPickerStyle) -> Bool {
        lhs.name == rhs.name && lhs.height == rhs.height && lhs.minimumSegmentWidth == rhs.minimumSegmentWidth
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(height)
        hasher.combine(minimumSegmentWidth)
    }
}
