import SwiftUI

struct OdeSpaceMenuLabelVisibility: ViewModifier {
    let labelsHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if labelsHidden {
            content.labelsHidden()
        } else {
            content
        }
    }
}
