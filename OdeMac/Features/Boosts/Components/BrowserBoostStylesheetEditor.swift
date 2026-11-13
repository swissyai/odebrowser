import SwiftUI

/// The CSS the person writes for a site, applied after the rest of its Boost.
struct BrowserBoostStylesheetEditor: View {
    let boost: BrowserBoostSession

    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(.vertical, OdeSpacing.small)
                .frame(width: 400, height: 220)
                .focused($isEditing)
                .odeFieldSurface(isFocused: isEditing)
                .accessibilityLabel("Custom CSS")
                .accessibilityIdentifier("boost-css")
                .onChange(of: text) { _, value in
                    if value.count > SiteBoost.maximumCustomCssLength {
                        text = String(value.prefix(SiteBoost.maximumCustomCssLength))
                    }
                }
            HStack {
                Spacer()
                Button("Apply") { apply() }
                    .buttonStyle(.odePrimary)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text == (boost.draft?.customCss ?? ""))
            }
        }
        .padding(OdeSpacing.medium)
        .onAppear { text = boost.draft?.customCss ?? "" }
        .onDisappear { apply() }
    }

    private func apply() {
        guard text != boost.draft?.customCss else { return }
        let css = text
        boost.change { $0.customCss = css }
    }
}
