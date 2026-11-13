import SwiftUI

struct BrowserAdvancedSetupActionButton: View {
    // MARK: - Variables

    let setupAction: BrowserAdvancedSetupAction

    @ViewBuilder
    var body: some View {
        if let help = setupAction.help {
            button.help(help)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: setupAction.action) {
            Label(setupAction.title, systemImage: setupAction.symbol)
                .foregroundStyle(OdeBrandTheme.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeHoverSurface(cornerRadius: OdeCornerScale.row)
        .odeAccessibilityIdentifier(setupAction.identifier)
    }
}
