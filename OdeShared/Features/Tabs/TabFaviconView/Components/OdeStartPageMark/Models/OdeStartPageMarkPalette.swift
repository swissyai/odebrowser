import SwiftUI

/// The mark's tile: the icon's warm paper in light and its dark ground in
/// dark. The mark's own colors are ``OdeMarkPalette``'s.
struct OdeStartPageMarkPalette {
    let background: Color

    init(colorScheme: ColorScheme) {
        background =
            colorScheme == .dark
            ? Color(red: 21 / 255, green: 21 / 255, blue: 22 / 255)
            : Color(red: 246 / 255, green: 245 / 255, blue: 240 / 255)
    }
}
