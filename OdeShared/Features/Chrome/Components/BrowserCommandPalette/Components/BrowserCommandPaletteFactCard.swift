import SwiftUI

/// A short answer below the search, as the Command Bar shows it: what it is
/// and its symbol, the answer itself, what it answers, and where it comes
/// from. A conversion leads with its result, a time card with the time there
/// and the day, a definition with its headword and pronunciation, and a
/// summary with its picture and credit. The selected card says what Return
/// does with it.
struct BrowserCommandPaletteFactCard: View {
    // MARK: - Static Variables

    private static let pictureSide: CGFloat = 56

    // MARK: - Variables

    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem
    let card: PaletteCard

    @Environment(\.browserChromeAppearance) private var chromeAppearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserInteractionCapabilities) private var capabilities

    private var isSelected: Bool { model.selectedResultIndex == item.index }
    private var isActionable: Bool { card.kind.copiesValue || card.kind.looksUpTerm || card.address != nil }
    private var canCopy: Bool {
        card.kind.copiesValue && ((card.kind != .translation && card.kind != .generativeAnswer) || card.value != nil)
    }
    private var isCopied: Bool { model.isCopied(item) }
    private var offersTabCopy: Bool { !capabilities.supportsTouch && model.tabCopyCandidate?.id == item.id }

    // MARK: - Actions - Presentation

    var body: some View {
        content
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
                        .primary.opacity(BrowserCommandPaletteMetrics.answerBorderOpacity),
                        lineWidth: OdeLayout.hairline)
            }
            .contentShape(.rect)
            .onTapGesture { model.selectResult(at: item.index) }
            .accessibilityElement(children: card.kind.copiesValue ? .contain : .combine)
            .accessibilityLabel(Text(verbatim: spoken))
            .accessibilityHint(isActionable ? Text(hint) : Text(verbatim: ""))
            .accessibilityAddTraits(isActionable && !card.kind.copiesValue ? .isButton : [])
            .accessibilityIdentifier("command-palette-card-\(card.kind.name)")
            .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }

    // MARK: - Actions - Parts

    @ViewBuilder
    private var content: some View {
        if canCopy, dynamicTypeSize.isAccessibilitySize {
            // Keep the answer at full width; its action must not squeeze
            // large text into a narrow column or split the Copy label.
            VStack(alignment: .leading, spacing: OdeSpacing.medium) {
                answer
                HStack(spacing: OdeSpacing.medium) {
                    leading
                    Spacer(minLength: OdeSpacing.medium)
                    controls
                }
            }
        } else {
            HStack(alignment: .top, spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                leading
                answer
                if canCopy {
                    controls
                } else if isActionable, !card.kind.copiesValue {
                    BrowserCommandPaletteRowTrailing(model: model, row: item.row, isSelected: isSelected)
                        .opacity(isSelected ? 1 : 0)
                }
            }
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
            // Keep equations and translation languages before their result,
            // but the Ode heading precedes its privacy context in every state.
            if card.value != nil, card.kind != .generativeAnswer, let detail { detailLine(detail) }
            headline
            if card.value == nil || card.kind == .generativeAnswer, let detail { detailLine(detail) }
            if card.body != nil {
                bodyText
                    .font(BrowserCommandPaletteMetrics.answerStepFont)
                    .lineLimit(card.kind == .translation || card.kind == .generativeAnswer ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            credits
            if card.kind == .translation || card.kind == .generativeAnswer, !canCopy { controls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyText: Text {
        if card.kind == .translation, card.value == nil { return Text(model.translationStatus.message) }
        if card.kind == .generativeAnswer, card.value == nil { return Text(LocalizedStringKey(card.body ?? "")) }
        return Text(verbatim: card.body ?? "")
    }

    @ViewBuilder
    private var controls: some View {
        if canCopy {
            copyButton
        } else if card.kind == .generativeAnswer, model.canRetryGenerativeAnswer {
            Button("Retry", systemImage: "arrow.clockwise", action: model.retryGenerativeAnswer)
                .buttonStyle(.odeTertiary(tint: .primary))
                .controlSize(.small)
                .focusEffectDisabled()
        } else if card.kind == .translation, model.canRetryTranslation {
            HStack(spacing: OdeSpacing.small) {
                if model.canDownloadTranslationLanguages {
                    Button(
                        "Download Languages", systemImage: "arrow.down.circle",
                        action: model.downloadTranslationLanguages)
                }
                Button("Retry", systemImage: "arrow.clockwise", action: model.retryTranslation)
            }
            .buttonStyle(.odeTertiary(tint: .primary))
            .controlSize(.small)
            .focusEffectDisabled()
        }
    }

    private var copyButton: some View {
        HStack(spacing: OdeSpacing.small) {
            BrowserCommandPaletteKeycap { Text("Tab") }
                .opacity(offersTabCopy ? 1 : 0)
                .accessibilityHidden(true)
            Button {
                model.copyCard(item)
            } label: {
                // Both labels keep their space so feedback never moves results.
                ZStack {
                    Label("Copy", systemImage: "doc.on.doc").opacity(isCopied ? 0 : 1)
                    Label("Copied", systemImage: "checkmark").opacity(isCopied ? 1 : 0)
                }
                .fixedSize(horizontal: true, vertical: false)
                .animation(OdeMotion.feedbackPresentation.unlessReducingMotion(reduceMotion), value: isCopied)
            }
            .buttonStyle(OdeButtonStyle(role: .secondary, tint: .primary))
            .controlSize(.small)
            .focusEffectDisabled()
            .disabled(!model.canCopyCard(item))
            .accessibilityLabel(isCopied ? Text("Copied") : Text("Copy answer"))
            .accessibilityValue(isCopied ? Text("Copied") : Text(verbatim: card.value ?? card.title))
            .accessibilityHint(offersTabCopy ? Text("Tab copies the answer.") : Text(verbatim: ""))
            .accessibilityIdentifier("command-palette-copy-answer-\(item.index)")
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let image = card.image, let picture = BrowserCommandPaletteCardImages.shared.image(for: image.address) {
            picture
                .resizable()
                .scaledToFill()
                .frame(width: Self.pictureSide, height: Self.pictureSide)
                .clipShape(.rect(cornerRadius: chromeAppearance.cornerScale.inset, style: .continuous))
                .accessibilityHidden(true)
        } else if card.kind.copiesValue || card.kind == .clarification {
            OdeMark(style: .mono)
                .frame(
                    width: BrowserCommandPaletteMetrics.rowFaviconSize,
                    height: BrowserCommandPaletteMetrics.rowFaviconSize
                )
                .frame(width: BrowserCommandPaletteMetrics.rowIconContainerSize)
        } else {
            Image(systemName: card.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.paletteDetail)
                .frame(minWidth: BrowserCommandPaletteMetrics.rowIconContainerSize)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let clock = card.clock {
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                Text(verbatim: BrowserCommandPaletteCardText.time(clock))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(verbatim: card.title).font(BrowserCommandPaletteMetrics.rowTitleFont)
            }
        } else if card.kind == .generativeAnswer {
            Text(card.kind.label).font(BrowserCommandPaletteMetrics.rowTitleFont)
        } else if card.value != nil {
            Text(verbatim: card.title)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                Text(verbatim: card.title).font(BrowserCommandPaletteMetrics.rowTitleFont)
                if !card.subtitle.isEmpty, card.kind == .definition {
                    Text(verbatim: card.subtitle).font(.callout).foregroundStyle(.paletteDetail)
                }
            }
        }
    }

    /// The line under the headline: what a conversion converted, the day
    /// and how far ahead a time is, or a summary's description.
    private var detail: String? {
        if let clock = card.clock {
            let day = BrowserCommandPaletteCardText.day(clock)
            if let given = BrowserCommandPaletteCardText.given(clock) {
                return "\(given) · \(day) · \(clock.difference)"
            }
            return "\(day) · \(clock.difference)"
        }
        if card.kind == .generativeAnswer { return String(localized: "Private · On device") }
        if card.kind == .definition { return nil }
        return card.subtitle.isEmpty ? nil : card.subtitle
    }

    @ViewBuilder
    private var credits: some View {
        let parts = [card.credit, card.license, card.image?.credit].compactMap { $0 }
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.paletteDetail)
                .lineLimit(2)
        }
    }

    private func detailLine(_ detail: String) -> some View {
        Text(verbatim: detail)
            .font(.callout)
            .foregroundStyle(.paletteDetail)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions - Accessibility

    private var spoken: String {
        if let clock = card.clock {
            return
                "\(card.title), \(BrowserCommandPaletteCardText.time(clock)), \(BrowserCommandPaletteCardText.day(clock))"
        }
        return [card.title, card.subtitle, card.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var hint: LocalizedStringResource {
        if card.kind == .generativeAnswer, !canCopy { return "The answer is not available to copy." }
        if card.kind == .translation, !canCopy { return "Return retries translation." }
        if card.kind.copiesValue { return "Return copies the answer." }
        if card.kind.looksUpTerm { return "Return opens the word in Dictionary." }
        return "Return opens the article."
    }
}
