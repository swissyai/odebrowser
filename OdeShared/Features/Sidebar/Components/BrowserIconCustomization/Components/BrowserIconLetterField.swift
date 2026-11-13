import SwiftUI

/// One letter or digit as an icon: whatever is typed becomes its first letter,
/// capitalized, and the field shows the letter the icon wears.
struct BrowserIconLetterField: View {
    let letter: String?
    let setLetter: (String) -> Void

    @State private var draft = ""

    var body: some View {
        HStack(spacing: OdeSpacing.small) {
            Image(systemName: "character")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Type a letter", text: $draft)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("browser-icon-letter-field")
                .onChange(of: draft) { _, typed in
                    guard let chosen = BrowserIconSymbol.normalizedLetter(typed) else { return }
                    if typed != chosen { draft = chosen }
                    setLetter(chosen)
                }
        }
        .padding(.leading, OdeSpacing.small)
        .padding(.trailing, OdeSpacing.extraSmall)
        .frame(minHeight: OdeLayout.minimumHitTarget)
        .background(.quaternary, in: .rect(cornerRadius: OdeRadius.control))
        .onAppear { draft = letter ?? "" }
    }
}
