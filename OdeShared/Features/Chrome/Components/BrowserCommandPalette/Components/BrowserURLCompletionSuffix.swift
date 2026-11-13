import SwiftUI

/// The rest of the address a completion proposes, drawn at the native caret
/// as selected text in the field's own font, without becoming part of the
/// editable value: Tab or Right Arrow accepts it, typing on replaces it.
struct BrowserURLCompletionSuffix: View {
    let text: String
    let font: Font
    var isVisible = true

    var body: some View {
        Group {
            if isVisible {
                Text(verbatim: text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxHeight: .infinity)
                    .background(Self.selection)
            }
        }
        // Each proposal is drawn fresh. Never animate the previous text or its
        // layout into the next keystroke's preview.
        .id(text)
        .transition(.identity)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The system's selected-text color, which the field's own selection wears.
    private static var selection: Color {
        #if os(macOS)
            Color(nsColor: .selectedTextBackgroundColor)
        #else
            Color(uiColor: .tintColor).opacity(0.25)
        #endif
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserURLCompletionSuffix(text: "browser.com", font: .title2).padding()
    }
#endif
