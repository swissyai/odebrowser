import CoreGraphics
import SwiftUI

enum BrowserCommandPaletteMetrics {
    static let maximumResultAreaHeight: CGFloat = 390
    static let resultOuterPadding: CGFloat = 28
    /// Rows sit close together on the Mac, where the pointer is precise, and
    /// keep a touch target on iPhone and iPad.
    #if os(macOS)
        static let resultRowHeight: CGFloat = 38
    #else
        static let resultRowHeight: CGFloat = 44
    #endif
    static let resultRowSpacing: CGFloat = 6
    static let resultHeaderHeight: CGFloat = 17
    static let resultSectionSpacing: CGFloat = 16

    static let overlayCardPadding: CGFloat = 24
    static var overlayReservedHeight: CGFloat {
        (overlayCardPadding * 2)
            + searchFieldMinimumHeight
    }
    static let minimumOverlayResultHeight: CGFloat = 82
    /// The room a palette grown out of an address field keeps from the edges
    /// of the space it lies in.
    static let fieldRegionMargin: CGFloat = 8
    /// The least room a palette rising to the top of the screen keeps there,
    /// where the safe area leaves less, as a Peek does.
    static let fieldRegionTopMargin: CGFloat = 10
    static let maximumCardWidth: CGFloat = 720
    /// The card's scale as it starts to appear in place.
    static let inPlaceArrivalScale: CGFloat = 0.98
    /// The panel's own color: white in light, a raised grey in dark that
    /// stands off dark pages.
    static let lightSurface = Color.white
    static let darkSurface = Color(red: 0.173, green: 0.173, blue: 0.180)
    /// How much of the panel's color covers the blurred page beneath it:
    /// enough to read as solid, with a trace of the page's color.
    static let surfaceOpacity = 0.94
    /// How far below full size the card's contents start while the card grows
    /// out of the address field, and end while it shrinks back.
    static let morphContentScale: CGFloat = 0.97

    static let searchFieldSpacing = rowSpacing
    static let searchFieldHorizontalPadding = rowHorizontalPadding
    static let searchFieldMinimumHeight: CGFloat = 60
    /// The rows sit one gutter inside the card, so their corners follow its.
    static let resultContentPadding = OdeCornerScale.gutter
    /// The least height of the row of search provider chips beside the field,
    /// which a larger text size makes taller.
    static let providerChipRowHeight: CGFloat = 44
    /// A provider's logo in a chip, and the neutral plate it sits on so it
    /// reads on any brand tint.
    static let chipIconSize: CGFloat = 14
    static let chipIconPlateSize: CGFloat = 20
    static let resultGroupSpacing = OdeSpacing.medium
    static let resultHeaderSpacing: CGFloat = 6
    static let resultHeaderHorizontalPadding: CGFloat = 4

    static let rowSpacing: CGFloat = 12
    /// A row's title, and what follows it on the same line.
    #if os(macOS)
        static let rowTitleFont = Font.body.weight(.medium)
        static let rowDetailFont = Font.body
    #else
        static let rowTitleFont = Font.body.weight(.semibold)
        static let rowDetailFont = Font.body
    #endif
    static let rowHorizontalPadding: CGFloat = 12
    static let selectedRowOpacity = 0.16
    static let restingRowOpacity = 0.0
    /// The solid pill a site wears once Tab enters it, and the soft glow of
    /// its color around it.
    static let providerPillHorizontalPadding: CGFloat = 10
    static let providerPillVerticalPadding: CGFloat = 4
    static let providerPillGlowRadius: CGFloat = 8
    static let providerPillGlowOpacity = 0.55

    static let rowIconContainerSize: CGFloat = 24
    static let rowFaviconSize: CGFloat = 18
    static let rowSymbolPointSize: CGFloat = 15
    /// The relative luminance of the panel a row's icon sits on.
    static let darkIconGroundLuminance = 0.026
    static let lightIconGroundLuminance = 1.0

    static let shortcutHorizontalPadding: CGFloat = 6
    static let shortcutMinimumHeight: CGFloat = 20
    static let shortcutCornerRadius = OdeCornerScale.keycap
    static let shortcutBackgroundOpacity = 0.07
    /// A key the field or a row names, such as Tab or the arrow that opens a
    /// row, drawn as a small keycap.
    static let keycapHorizontalPadding: CGFloat = 6
    static let keycapMinimumSide: CGFloat = 22
    static let keycapBackgroundOpacity = 0.1

    static let scrimOpacity = 0.18

    /// A written answer: its steps' type, the faint tone of the selected
    /// answer and the hairline around every answer, and the coral of its
    /// symbol and of the button Return runs.
    #if os(macOS)
        static let answerStepFont = Font.body
    #else
        static let answerStepFont = Font.callout
    #endif
    static let answerSelectedOpacity = 0.05
    static let answerBorderOpacity = 0.1
    static let answerAccent = OdeBrandPalette.coral
    static let answerFill = BrowserSearchProviderFill(
        brand: BrandColor(
            red: Double(OdeBrandPalette.coralComponents.red) / 255,
            green: Double(OdeBrandPalette.coralComponents.green) / 255,
            blue: Double(OdeBrandPalette.coralComponents.blue) / 255, alpha: 1))
}
