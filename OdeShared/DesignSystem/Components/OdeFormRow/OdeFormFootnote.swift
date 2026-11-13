import SwiftUI

/// The shared explanatory-copy treatment used beneath form controls.
struct OdeFormFootnote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text).odeFormFootnote()
    }
}

#if DEBUG
    #Preview("Component") {
        OdeFormFootnote("Startup choices take effect the next time Ode opens a window.").padding().frame(width: 340)
    }
#endif
