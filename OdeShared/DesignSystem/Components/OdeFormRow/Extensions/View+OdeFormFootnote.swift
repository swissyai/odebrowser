import SwiftUI

extension View {
    /// Applies the explanatory-copy role to content assembled by the caller.
    func odeFormFootnote() -> some View {
        font(.footnote)
            .foregroundStyle(OdeColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
