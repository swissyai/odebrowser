import SwiftUI

struct BrowserEmojiCategoryBar: View {
    @Binding var category: BrowserEmojiCategory
    let contentWidth: CGFloat

    var body: some View {
        VStack(spacing: OdeSpacing.small) {
            Divider()
                .padding(.horizontal, OdeSpacing.extraSmall)

            ScrollView(.horizontal) {
                HStack(spacing: OdeSpacing.extraSmall) {
                    ForEach(BrowserEmojiCategory.all) { option in
                        Button {
                            category = option
                        } label: {
                            Image(systemName: option.symbol)
                                .frame(
                                    width: OdeLayout.minimumHitTarget,
                                    height: OdeLayout.minimumHitTarget
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .odeControlPointer()
                        .foregroundStyle(
                            category == option
                                ? Color.accentColor : Color.secondary
                        )
                        .background(
                            category == option ? OdeColor.hover : .clear,
                            in: .rect(cornerRadius: OdeRadius.compact)
                        )
                        .help(Text(option.title))
                        .accessibilityLabel(Text(option.title))
                        .accessibilityValue(
                            category == option ? "Selected" : ""
                        )
                    }
                }
                .frame(
                    minWidth: contentWidth - OdeSpacing.small * 2,
                    alignment: .center
                )
            }
            .contentMargins(
                .horizontal,
                OdeSpacing.small,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: contentWidth)
        .accessibilityIdentifier("browser-emoji-category-bar")
    }

}

#if DEBUG
    #Preview("Choose a category") {
        @Previewable @State var category: BrowserEmojiCategory = .nature
        BrowserEmojiCategoryBar(category: $category, contentWidth: 320).padding()
    }
#endif
