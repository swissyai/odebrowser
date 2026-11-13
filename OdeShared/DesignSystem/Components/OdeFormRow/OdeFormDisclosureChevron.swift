import SwiftUI

/// Direction-aware disclosure indicator for a row that navigates or presents.
struct OdeFormDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(OdeTypography.metadata.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Component") {
        OdeFormDisclosureChevron().padding()
    }
#endif
