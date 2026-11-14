import SwiftUI

/// Symbols and emoji suggested for the name an icon is for: one row of
/// each, above the search, marking the one already chosen.
struct BrowserIconSuggestionRows: View {
    let name: String
    let suggestions: SpaceIconSuggestions
    let currentSystemSymbol: String?
    let currentEmoji: String?
    let selectSystemSymbol: ((String) -> Void)?
    let selectEmoji: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            Text("Suggested for “\(name)”")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let selectSystemSymbol, !suggestions.symbols.isEmpty {
                row(suggestions.symbols) { symbol in
                    cell(
                        isSelected: symbol == currentSystemSymbol, help: symbol.replacingOccurrences(of: ".", with: " ")
                    ) {
                        selectSystemSymbol(symbol)
                    } label: {
                        Image(systemName: symbol).font(.body)
                    }
                    .accessibilityIdentifier("browser-icon-suggested-symbol-\(symbol)")
                }
            }
            if !suggestions.emoji.isEmpty {
                row(suggestions.emoji) { emoji in
                    cell(isSelected: emoji == currentEmoji, help: emoji) {
                        selectEmoji(emoji)
                    } label: {
                        Text(emoji).font(.title3)
                    }
                    .accessibilityIdentifier("browser-icon-suggested-emoji")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested for \(name)")
    }

    private func row<Content: View>(_ items: [String], @ViewBuilder content: @escaping (String) -> Content)
        -> some View
    {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: BrowserIconPickerLayout.cellSize),
                    spacing: BrowserIconPickerLayout.gridSpacing)
            ],
            alignment: .leading, spacing: BrowserIconPickerLayout.gridSpacing
        ) {
            ForEach(items.prefix(BrowserIconPickerLayout.suggestionCount), id: \.self, content: content)
        }
    }

    private func cell<Label: View>(
        isSelected: Bool, help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: BrowserIconPickerLayout.cellSize, height: BrowserIconPickerLayout.cellSize)
                .background(
                    isSelected ? Color.accentColor.opacity(BrowserIconPickerLayout.selectedFillOpacity) : .clear,
                    in: .rect(cornerRadius: OdeCornerScale.inset, style: .continuous)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: OdeCornerScale.inset, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: BrowserIconPickerLayout.selectedBorderWidth)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeControlPointer()
        .help(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
    #Preview("Suggestions for Work") {
        BrowserIconSuggestionRows(
            name: "Work",
            suggestions: SpaceIconSuggestions(
                symbols: ["briefcase", "laptopcomputer", "building.2", "desktopcomputer", "chart.bar", "target"],
                emoji: ["💼", "💻", "🏢", "🖥️", "📊", "👔"]),
            currentSystemSymbol: "briefcase", currentEmoji: nil, selectSystemSymbol: { _ in }, selectEmoji: { _ in }
        )
        .padding().frame(width: 320)
    }
#endif
