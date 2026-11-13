import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal Clear on hover. Touch shells center its hit target
/// on the line, using the saved drop band as the space above it. Tidy sits
/// beside Clear, revealed the same way, only while it is offered.
struct BrowserCurrentTabsDivider: View {
    // MARK: - Static Variables

    /// The line Tidy covers beside Clear's, with the gap between them.
    private static let tidyActionOcclusionWidth: CGFloat = 52

    // MARK: - Variables

    let capabilities: BrowserInteractionCapabilities
    var hasSavedTabsEndBand = false
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether there is anything left to clear.
    let canClear: Bool
    let clear: () -> Void
    /// The open tabs Tidy offers to group, read when Tidy opens. `nil` hides
    /// Tidy, as it is while intelligence is off.
    var tidyTabs: (() -> [BrowserTidyToday.Tab])? = nil
    /// Files the folders and closes the duplicates the person applied.
    var applyTidy: (_ groups: [BrowserTidyToday.Group], _ duplicates: [BrowserTidyToday.Tab]) -> Void = { _, _ in }
    @Environment(\.displayScale) private var displayScale
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme
    @State private var isTidying = false
    @State private var tabsToTidy: [BrowserTidyToday.Tab] = []

    private var metrics: BrowserSidebarTabListMetrics {
        capabilities.tabListMetrics
    }

    var body: some View {
        Group {
            if revealsOnHoverOnly {
                ZStack(alignment: .trailing) {
                    line
                    trailingControls
                }
                .padding(.vertical, metrics.dividerVerticalInset)
            } else {
                line
                    .overlay(alignment: .trailing) { trailingControls }
                    .padding(
                        .top,
                        hasSavedTabsEndBand ? max(0, touchSpacing - metrics.savedSectionEndBandHeight) : touchSpacing
                    )
                    .padding(.bottom, touchSpacing)
            }
        }
        .padding(.horizontal, metrics.dividerHorizontalInset)
        .sheet(isPresented: $isTidying) {
            BrowserTidyTodaySheet(tidy: BrowserTidyToday(tabs: tabsToTidy), apply: applyTidy)
        }
    }

    /// One pixel of the Space's separator. A system divider underneath would
    /// draw its own point-wide line through it.
    private var line: some View {
        Rectangle()
            .fill(spaceColorRoles?.applying(in: colorScheme)?.separator.color ?? OdeColor.subtleBorder)
            .frame(height: 1 / max(displayScale, 1))
            .frame(maxWidth: .infinity)
            .padding(.trailing, showsClearButton ? occlusionWidth : 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingControls: some View {
        if tidyTabs != nil {
            HStack(spacing: 8) {
                tidyButton
                clearButton
            }
        } else {
            clearButton
        }
    }

    private var tidyButton: some View {
        Button {
            tabsToTidy = tidyTabs?() ?? []
            isTidying = true
        } label: {
            HStack(spacing: 4) {
                if revealsOnHoverOnly { Text("Tidy") }
                Image(systemName: "sparkles")
            }
            .frame(minWidth: revealsOnHoverOnly ? nil : 44, minHeight: revealsOnHoverOnly ? nil : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(SpaceRoleStyle.secondaryText)
        .fixedSize()
        .opacity(showsClearButton ? 1 : 0)
        .disabled(!canClear || !showsClearButton)
        .accessibilityHidden(!showsClearButton)
        .accessibilityLabel("Tidy Open Tabs")
        .accessibilityHint("Suggests folders for the current tabs")
    }

    private var clearButton: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                if revealsOnHoverOnly { Text("Clear") }
                Image(systemName: "archivebox")
                Image(systemName: "arrow.down")
            }
            .frame(minWidth: revealsOnHoverOnly ? nil : 44, minHeight: revealsOnHoverOnly ? nil : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(SpaceRoleStyle.secondaryText)
        .fixedSize()
        .opacity(showsClearButton ? 1 : 0)
        .disabled(!canClear || !showsClearButton)
        .accessibilityHidden(!showsClearButton)
        .accessibilityLabel("Clear Open Tabs")
        .accessibilityHint("Moves all current tabs to Archive")
    }

    private var occlusionWidth: CGFloat {
        metrics.clearActionOcclusionWidth + (tidyTabs != nil ? Self.tidyActionOcclusionWidth : 0)
    }

    private var touchSpacing: CGFloat {
        max(22, metrics.dividerVerticalInset)
    }

    private var showsClearButton: Bool {
        !revealsOnHoverOnly || (showsClearAction && canClear)
    }

    private var revealsOnHoverOnly: Bool {
        capabilities.revealsRowControlsOnHoverOnly
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCurrentTabsDivider(
            capabilities: BrowserInteractionCapabilities(), showsClearAction: true, canClear: true, clear: {}
        ).padding().frame(width: 320)
    }
#endif
