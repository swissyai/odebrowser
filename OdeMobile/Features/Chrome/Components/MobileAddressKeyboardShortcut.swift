import SwiftUI

/// A piece of an address the row above the keyboard types in one tap, which
/// a phone keyboard otherwise keeps on its second layer.
struct MobileAddressKeyboardShortcut: Equatable, Hashable, Sendable {
    // MARK: - Static Variables

    static let dotCom = MobileAddressKeyboardShortcut(title: ".com", fragment: ".com")
    static let slash = MobileAddressKeyboardShortcut(title: "/", fragment: "/")

    /// The shortcuts in the order the row shows them.
    static let all = [dotCom, slash]

    // MARK: - Variables

    /// What the key shows, which is what it types.
    let title: String
    let fragment: String

    // MARK: - Initializers

    private init(title: String, fragment: String) {
        self.title = title
        self.fragment = fragment
    }

    // MARK: - Actions - Typing

    /// `text` with the fragment typed at its end, without doubling the dot or
    /// slash the text already ends with.
    func applied(to text: String) -> String {
        guard let first = fragment.first, text.last == first else { return text + fragment }
        return text + fragment.dropFirst()
    }
}

/// The address a row above the keyboard edits, which the field it belongs to
/// provides while the person types in it.
struct MobileAddressKeyboardRow {
    let text: Binding<String>
}

extension EnvironmentValues {
    /// The address the keyboard's row edits, or nil where the field shows no
    /// row.
    @Entry var mobileAddressKeyboardRow: MobileAddressKeyboardRow?
}

/// Paste, then the shortcuts, on the bar iOS attaches to the keyboard.
struct MobileAddressKeyboardRowContent: View {
    let row: MobileAddressKeyboardRow

    var body: some View {
        // The system's paste control reads the clipboard only when tapped, so
        // it never asks for permission to paste.
        PasteButton(payloadType: String.self) { strings in
            guard
                let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                !pasted.isEmpty
            else { return }
            row.text.wrappedValue = pasted
        }
        .labelStyle(.titleAndIcon)

        Spacer()

        ForEach(MobileAddressKeyboardShortcut.all, id: \.self) { shortcut in
            Button(shortcut.title) {
                row.text.wrappedValue = shortcut.applied(to: row.text.wrappedValue)
            }
            .accessibilityLabel(Text(verbatim: shortcut.title))
        }
    }
}
