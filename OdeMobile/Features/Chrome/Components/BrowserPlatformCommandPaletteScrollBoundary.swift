import SwiftUI

/// Touch scrolling follows the mobile shell's own presentation.
struct BrowserPlatformCommandPaletteScrollBoundary: View {
    var body: some View { Color.clear.allowsHitTesting(false).accessibilityHidden(true) }
}
