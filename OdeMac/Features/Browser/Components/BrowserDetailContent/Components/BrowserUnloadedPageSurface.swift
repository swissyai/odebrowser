import SwiftUI

/// A tab whose page has not come yet: the background its site painted last,
/// when Ode remembers one, so the window never shows another colour first.
struct BrowserUnloadedPageSurface: View {
    var background: BrowserPageBackground? = nil

    var body: some View {
        (background.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
