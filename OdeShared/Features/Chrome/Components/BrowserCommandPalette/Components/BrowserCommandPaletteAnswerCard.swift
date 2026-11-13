import SwiftUI

/// A written answer as the Command Bar shows it: its title and the keys that
/// do the same thing, its steps, numbered when they are a procedure, its
/// caveat, then "Read More" and "Do It". The button Return runs is Ode's
/// primary button in coral, darkened as far as white text needs; Tab moves
/// between the buttons and Escape closes the bar.
struct BrowserCommandPaletteAnswerCard: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem
    let card: AnswerCard

    @Environment(\.browserChromeAppearance) private var chromeAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserInteractionCapabilities) private var capabilities

    private var isSelected: Bool { model.selectedResultIndex == item.index }

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            header
            steps
                .padding(
                    .leading,
                    BrowserCommandPaletteMetrics.rowIconContainerSize + BrowserCommandPaletteMetrics.rowSpacing)
            if let note = card.note {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.panelDetail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(
                        .leading,
                        BrowserCommandPaletteMetrics.rowIconContainerSize + BrowserCommandPaletteMetrics.rowSpacing)
            }
            controls
        }
        .padding(.horizontal, BrowserCommandPaletteMetrics.rowHorizontalPadding)
        .padding(.vertical, OdeSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(isSelected ? BrowserCommandPaletteMetrics.answerSelectedOpacity : 0),
            in: .rect(cornerRadius: chromeAppearance.cornerScale.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.row, style: .continuous)
                .strokeBorder(
                    .primary.opacity(BrowserCommandPaletteMetrics.answerBorderOpacity), lineWidth: OdeLayout.hairline)
        }
        .contentShape(.rect)
        .onTapGesture { model.selectResult(at: item.index) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: card.title))
        .accessibilityIdentifier("command-palette-answer-\(card.id)")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
        .animation(
            reduceMotion ? nil : .snappy(duration: OdeMotion.hoverTransition), value: model.answerControl(for: item))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrowserCommandPaletteMetrics.rowSpacing) {
            Image(systemName: "questionmark.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(BrowserCommandPaletteMetrics.answerAccent)
                .frame(width: BrowserCommandPaletteMetrics.rowIconContainerSize)
                .accessibilityHidden(true)
            Text(verbatim: card.title)
                .font(BrowserCommandPaletteMetrics.rowTitleFont)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: OdeSpacing.small)
            keys
        }
    }

    /// The keys that do what the answer describes: the person's own for its
    /// command, else the default the answer names.
    @ViewBuilder
    private var keys: some View {
        if !capabilities.supportsTouch {
            if let command = card.action?.command, let chord = model.commands?.shortcut(for: command) {
                BrowserCommandPaletteKeycap { Text(verbatim: chord.displayString) }
                    .accessibilityLabel(Text("Shortcut \(chord.spokenDescription)"))
            } else if let keys = card.keys {
                BrowserCommandPaletteKeycap { Text(verbatim: keys) }
                    .accessibilityLabel(Text("Shortcut \(keys)"))
            }
        }
    }

    @ViewBuilder
    private var steps: some View {
        if card.kind.numbersSteps && card.steps.count > 1 {
            VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                ForEach(Array(card.steps.enumerated()), id: \.offset) { number, step in
                    HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                        Text(verbatim: "\(number + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.panelDetail)
                            .accessibilityHidden(true)
                        Text(verbatim: step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Step \(number + 1): \(step)"))
                }
            }
            .font(BrowserCommandPaletteMetrics.answerStepFont)
        } else {
            Text(verbatim: card.steps.joined(separator: " "))
                .font(BrowserCommandPaletteMetrics.answerStepFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: OdeSpacing.small) {
            Spacer(minLength: 0)
            ForEach(BrowserCommandPaletteAnswerControl.offered(for: card, in: model).reversed(), id: \.name) {
                control in
                let runsOnReturn = isSelected && model.answerControl(for: item) == control
                let fill = BrowserCommandPaletteMetrics.answerFill.fillColor
                let style: OdeButtonStyle = runsOnReturn ? .odePrimary(tint: fill) : .odeTertiary(tint: .primary)
                Button {
                    model.run(control, of: item)
                } label: {
                    HStack(spacing: OdeSpacing.extraSmall) {
                        Text(control.title)
                        if runsOnReturn && !capabilities.supportsTouch {
                            Image(systemName: "return")
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(style)
                // The field keeps the keyboard: Tab moves between these
                // buttons, so they take no focus of their own.
                .focusEffectDisabled()
                .accessibilityHint(Text(control.hint))
                .accessibilityAddTraits(runsOnReturn ? .isSelected : [])
                .accessibilityIdentifier("command-palette-answer-\(control.name)")
            }
        }
    }
}
