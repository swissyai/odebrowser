import SwiftUI

struct BrowserNavigationFailureRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(OdeBrandTheme.accent)
            .accessibilityHint("Retries the failed address")
            .accessibilityIdentifier("navigation-failure-retry")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureRetryButton(action: {}).padding()
    }
#endif
