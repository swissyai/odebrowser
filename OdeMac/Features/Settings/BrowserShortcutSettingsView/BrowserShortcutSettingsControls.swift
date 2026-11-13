import AppKit
import SwiftUI

struct BrowserShortcutSettingsControls: View {
    @Binding var searchText: String

    let canReset: Bool
    let requestReset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                search.frame(minWidth: 200)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                search
                actions
            }
        }
    }

    private var search: some View {
        BrowserShortcutSearchField(
            text: $searchText,
            placeholder: BrowserShortcutSettingsPresentation.searchPrompt,
            identifier: BrowserShortcutSettingsAccessibilityID.search
        )
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(BrowserShortcutSettingsPresentation.resetOde, action: requestReset)
                .disabled(!canReset)
                .accessibilityIdentifier(BrowserShortcutSettingsAccessibilityID.resetAll)
        }
        .fixedSize()
    }

}

private struct BrowserShortcutSearchField: NSViewRepresentable {
    @Environment(\.locale) private var locale

    @Binding var text: String

    let placeholder: LocalizedStringResource
    let identifier: String

    func makeCoordinator() -> BrowserShortcutSearchFieldCoordinator {
        BrowserShortcutSearchFieldCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .regular
        field.placeholderString = BrowserShortcutLocalization.string(
            placeholder,
            locale: locale
        )
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        // Setting the placeholder while the field edits restarts its editing;
        // set it only when it differs.
        let localizedPlaceholder = BrowserShortcutLocalization.string(placeholder, locale: locale)
        if field.placeholderString != localizedPlaceholder {
            field.placeholderString = localizedPlaceholder
        }
        context.coordinator.text = $text
    }
}

@MainActor
private final class BrowserShortcutSearchFieldCoordinator:
    NSObject,
    NSSearchFieldDelegate
{
    var text: Binding<String>

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else {
            return
        }
        text.wrappedValue = field.stringValue
    }
}
