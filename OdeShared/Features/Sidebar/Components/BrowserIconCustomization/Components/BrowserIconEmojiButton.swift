import SwiftUI

struct BrowserIconEmojiButton: View {
    let choice: BrowserTabEmojiChoice
    let currentEmoji: String?
    @Binding var variantChoice: BrowserTabEmojiChoice?
    let selectEmoji: (String) -> Void

    private var isSelected: Bool { currentEmoji == choice.emoji }

    var body: some View {
        let button = Button {
            selectEmoji(choice.emoji)
        } label: {
            Text(choice.emoji)
                .font(.title3)
                .frame(width: BrowserIconPickerLayout.cellSize, height: BrowserIconPickerLayout.cellSize)
                .contentShape(.rect)
        }
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
        .odeControlPointer()
        .help(choice.name)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if choice.variants.isEmpty {
            button.buttonStyle(.plain)
        } else {
            button.modifier(
                BrowserPlatformEmojiVariantModifier(
                    choice: choice, isPresented: variantPopoverBinding,
                    selectEmoji: selectEmojiVariant))
        }
    }

    private var variantPopoverBinding: Binding<Bool> {
        Binding(
            get: { variantChoice?.id == choice.id },
            set: { isPresented in
                if isPresented {
                    variantChoice = choice
                } else if variantChoice?.id == choice.id {
                    variantChoice = nil
                }
            })
    }

    private func selectEmojiVariant(_ emoji: String) {
        variantChoice = nil
        selectEmoji(emoji)
    }
}

#if DEBUG
    #Preview("Emoji selection") {
        @Previewable @State var variant: BrowserTabEmojiChoice?
        @Previewable @State var selected: String? = "🌊"
        HStack {
            BrowserIconEmojiButton(
                choice: BrowserTabEmojiChoice(emoji: "🌊", name: "Water wave", category: .nature),
                currentEmoji: selected, variantChoice: $variant, selectEmoji: { selected = $0 })
            BrowserIconEmojiButton(
                choice: BrowserTabEmojiChoice(emoji: "🌿", name: "Herb", category: .nature), currentEmoji: selected,
                variantChoice: $variant, selectEmoji: { selected = $0 })
        }.padding()
    }
#endif
