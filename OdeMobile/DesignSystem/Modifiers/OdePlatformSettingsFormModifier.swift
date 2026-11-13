import SwiftUI
import UIKit

/// Mobile Settings follows the system grouped-form canvas.
struct OdePlatformSettingsFormModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .frame(maxWidth: maxWidth)
    }
}
