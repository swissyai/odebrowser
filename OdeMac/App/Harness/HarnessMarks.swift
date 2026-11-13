#if DEBUG || ODE_REVIEW_BUILD

    import SwiftUI

    /// The mark at each of `sides`, side by side on the window's background.
    struct HarnessMarks: View {
        // MARK: - Variables

        let sides: [CGFloat]

        // MARK: - Actions - Content

        var body: some View {
            HStack(alignment: .bottom, spacing: OdeSpacing.large) {
                ForEach(sides, id: \.self) { side in
                    OdeMark().frame(width: side, height: side)
                }
            }
            .padding(OdeSpacing.large)
        }
    }

#endif
