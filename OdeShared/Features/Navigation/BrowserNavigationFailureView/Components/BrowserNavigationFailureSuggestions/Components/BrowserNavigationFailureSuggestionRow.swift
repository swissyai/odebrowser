import SwiftUI

/// One thing to try, led by a small Ode blue arrow: a step to take, not a
/// check of one already done.
struct BrowserNavigationFailureSuggestionRow: View {
    let suggestion: LocalizedStringResource

    var body: some View {
        Label {
            Text(suggestion)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.forward")
                .font(.callout.weight(.semibold))
                .foregroundStyle(OdeBrandTheme.accentText)
                .accessibilityHidden(true)
        }
        .font(.callout)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureSuggestionRow(
            suggestion: "Check your internet connection and try again."
        ).padding().frame(width: 360)
    }
#endif
