import CoreGraphics

/// Measurements shared by every resettable settings row.
enum OdeSettingRowMetrics {
    static let controlSpacing = OdeSpacing.small
    /// Space between a slider's title/value row and its full-width track.
    static let sliderSpacing = OdeSpacing.small
    /// The fixed track of a slider that shares one line with its title.
    static let inlineSliderWidth: CGFloat = 160
    /// The live value beside an inline slider, wide enough for "Borderless".
    static let sliderReadoutWidth: CGFloat = 76
}
