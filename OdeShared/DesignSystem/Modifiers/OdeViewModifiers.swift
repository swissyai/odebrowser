import SwiftUI

private struct BrowserReadableForegroundModifier: ViewModifier {
    let background: Color

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.foregroundStyle(background.readableForeground(environment: environment))
    }
}

private struct BrowserTabResidencyModifier: ViewModifier {
    let isLoaded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isLoaded && BrowserDeviceAppearanceStore.shared.tabs.dimsUnloadedTabs {
            content.foregroundStyle(SpaceRoleStyle.secondaryText)
        } else {
            content
        }
    }
}

private struct OdeOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier, identifier.contains(where: { !$0.isWhitespace }) {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

extension View {
    func browserReadableForeground(over background: Color) -> some View {
        modifier(BrowserReadableForegroundModifier(background: background))
    }

    /// Optionally draws the text and symbols that stand for a tab the shell is
    /// not holding in memory in the Space's secondary role, the cue a row
    /// gives while "Dim unloaded tabs" is on.
    ///
    /// Never applied to a site's icon, which keeps its own colors at full
    /// strength, loaded or not, in rows and pinned tiles alike. Applied to the
    /// pieces that *describe* a row's tab rather than to the row as a whole,
    /// so a mark drawn over one of them can stay out of the treatment. An
    /// unloaded tab still holds its extension side panel, and the badge saying
    /// so keeps full strength.
    func browserTabResidency(isLoaded: Bool) -> some View {
        modifier(BrowserTabResidencyModifier(isLoaded: isLoaded))
    }

    /// Applies an identifier only when one is supplied, preserving any identifier
    /// already published by the wrapped control.
    func odeAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(OdeOptionalAccessibilityIdentifier(identifier: identifier))
    }

    /// Keeps action menus consistent across Apple platforms. Every Ode-authored
    /// menu action supplies an icon when a meaningful symbol, Ode, or logo is
    /// available. Apply this to the action builder *inside* each `Menu` or
    /// `contextMenu`: native menu presentation is a boundary, so styling only the
    /// revealing control does not reliably reach submenu rows on macOS.
    func odeMenuActionLabelStyle() -> some View {
        labelStyle(.titleAndIcon)
    }

    /// Sizes a sheet: a window frame on the Mac, and on touch a half-height
    /// detent that stretches to full height.
    func odeSheetSize(
        minWidth: CGFloat, idealWidth: CGFloat? = nil, minHeight: CGFloat, idealHeight: CGFloat? = nil
    ) -> some View {
        #if os(macOS)
            frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight, idealHeight: idealHeight)
        #else
            presentationDetents([.medium, .large])
        #endif
    }
}
