import SwiftUI

/// macOS Settings keeps the form canvas transparent inside its window chrome.
struct OdePlatformSettingsFormModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(maxWidth: maxWidth)
    }
}
