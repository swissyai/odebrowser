import SwiftUI

/// What a row says at its end: where Return opens it while the person holds
/// modifier keys, else, on the selected row, what Shift-Return does to it,
/// else its command's shortcut, its kind in the blended layout, or what
/// activating it does, such as "Switch to Tab". The selected row, and a row
/// that says what it does, end with a keycap: Return's glyph for where Return
/// opens the selected row, an arrow on the others.
struct BrowserCommandPaletteRowTrailing: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow
    var isSelected = false
    var namesKind = false

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesCompactTouchLayout: Bool { capabilities.supportsTouch && horizontalSizeClass == .compact }
    private var showsKeyboardHints: Bool { !capabilities.supportsTouch }

    var body: some View {
        HStack(spacing: OdeSpacing.small) {
            // A held-key opening is a distinct outcome, not redundant row copy.
            if !usesCompactTouchLayout || (isSelected && model.selectedOpening.title != nil) {
                trailingText.fixedSize(horizontal: usesCompactTouchLayout, vertical: false)
            }

            // A suggestion says what it does only while selected, so the
            // list of them reads as plain words.
            if isSelected ? showsKeyboardHints : row.kind.action != nil && row.kind != .searchSuggestion {
                BrowserCommandPaletteKeycap {
                    Image(systemName: isSelected ? model.selectedOpening.symbol : "arrow.right")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityHidden(true)
            }
        }
        .animation(.snappy(duration: OdeMotion.hoverTransition), value: model.selectedOpening)
    }

    private var trailingText: some View {
        Group {
            if isSelected, let title = model.selectedOpening.title {
                Text(title)
                    .font(BrowserCommandPaletteMetrics.rowDetailFont.weight(.medium))
                    .foregroundStyle(.primary)
                    .transition(.blurReplace)
            } else if isSelected, showsKeyboardHints, let hint = model.shiftReturnOpening(for: row)?.hint {
                shiftReturnHint(hint)
            } else if showsKeyboardHints, let command = row.command,
                let chord = model.commands?.shortcut(for: command)
            {
                Text(verbatim: chord.displayString)
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundStyle(.paletteDetail)
                    .padding(
                        .horizontal,
                        BrowserCommandPaletteMetrics.shortcutHorizontalPadding
                    )
                    .frame(minHeight: BrowserCommandPaletteMetrics.shortcutMinimumHeight)
                    .background(
                        .primary.opacity(
                            BrowserCommandPaletteMetrics.shortcutBackgroundOpacity
                        ),
                        in: .rect(
                            cornerRadius: BrowserCommandPaletteMetrics.shortcutCornerRadius
                        )
                    )
                    .accessibilityLabel(Text(verbatim: chord.spokenDescription))
            } else if namesKind {
                Text(row.kind.label)
                    .font(BrowserCommandPaletteMetrics.rowDetailFont)
                    .foregroundStyle(.paletteDetail)
            } else if let action = row.kind.action, row.kind != .searchSuggestion {
                Text(action)
                    .font(BrowserCommandPaletteMetrics.rowDetailFont)
                    .foregroundStyle(.paletteDetail)
            }
        }
        .lineLimit(1)
    }

    /// Shift-Return's keys, then what they do to the row.
    private func shiftReturnHint(_ hint: LocalizedStringResource) -> some View {
        HStack(spacing: OdeSpacing.extraSmall) {
            HStack(spacing: 1) {
                Image(systemName: "shift")
                Image(systemName: "return")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, BrowserCommandPaletteMetrics.shortcutHorizontalPadding)
            .frame(minHeight: BrowserCommandPaletteMetrics.shortcutMinimumHeight)
            .background(
                .primary.opacity(BrowserCommandPaletteMetrics.shortcutBackgroundOpacity),
                in: .rect(cornerRadius: BrowserCommandPaletteMetrics.shortcutCornerRadius))
            Text(hint)
                .font(BrowserCommandPaletteMetrics.rowDetailFont)
        }
        .foregroundStyle(.paletteDetail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Shift-Return: \(hint)"))
        .accessibilityIdentifier("command-palette-shift-return-hint")
    }
}

#if DEBUG
    #Preview("Command shortcut") {
        BrowserCommandPaletteRowTrailing(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"),
            row: BrowserCommandPalettePreviewFixture.commandRow
        ).padding()
    }
#endif
