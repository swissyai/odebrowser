import SwiftUI

/// Shared symbol catalog for Space artwork and sidebar folder icons: curated
/// sections and then every symbol while nothing is typed, or the ranked
/// results of a search.
struct BrowserSystemSymbolCatalogGrid: View {
    let selection: String?
    let query: String
    /// The catalog, once it has loaded off the main actor.
    let catalog: BrowserIconCatalog?
    /// The symbols a search found, best first; nil while nothing is typed.
    let results: [String]?
    let select: (String) -> Void

    private static let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                    if let results {
                        ForEach(results, id: \.self, content: cell)
                    } else if let catalog {
                        ForEach(catalog.popularSections) { section in
                            Section {
                                ForEach(section.symbols, id: \.self, content: cell)
                            } header: {
                                header(Text(section.title))
                            }
                        }
                        Section {
                            ForEach(catalog.symbolNames, id: \.self, content: cell)
                        } header: {
                            header(Text("All symbols"))
                        }
                    }
                }
                .padding(2)
            }
            .overlay {
                if catalog == nil {
                    ProgressView("Loading symbols…")
                } else if let results, results.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Text("\(results?.count ?? catalog?.symbolNames.count ?? 0) symbols")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func header(_ title: Text) -> some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OdeSpacing.small)
    }

    private func cell(_ name: String) -> some View {
        let isSelected = selection == name
        return Button {
            select(name)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: name)
                    .resizable().scaledToFit()
                    .frame(width: 32, height: 32)
                    .frame(height: 36)
                Text(name.replacingOccurrences(of: ".", with: " "))
                    .font(.caption2).lineLimit(2).frame(height: 30)
            }
            .frame(maxWidth: .infinity).padding(8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(BrowserIconPickerLayout.selectedFillOpacity) : .primary.opacity(0.035),
                in: .rect(cornerRadius: OdeCornerScale.row, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).strokeBorder(
                        Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain).help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
    #Preview("Symbol catalog") {
        @Previewable @State var selection = "briefcase.fill"
        BrowserSystemSymbolCatalogGrid(
            selection: selection, query: "",
            catalog: BrowserIconCatalog(
                symbolNames: ["briefcase.fill", "house.fill", "star.fill", "globe", "leaf.fill", "heart.fill"],
                emojiChoices: [], concepts: [], emojiKeywords: [:]),
            results: nil, select: { selection = $0 }
        )
        .padding().frame(width: 480, height: 500)
    }
#endif
