import SwiftUI

extension View {
    func odeSettingsForm(
        maxWidth: CGFloat = BrowserSettingsLayout.maximumReadableContentWidth
    ) -> some View {
        modifier(OdePlatformSettingsFormModifier(maxWidth: maxWidth))
    }
}
