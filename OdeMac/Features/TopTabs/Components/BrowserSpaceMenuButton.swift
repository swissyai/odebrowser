import SwiftUI

/// The Space the window shows, in its own color, opening to switch to another
/// Space or make a new one: at the leading end of the bar of tabs on top, and
/// at the foot of the sidebar as icons. Control-1 to Control-9 and the Space
/// keys switch Spaces as they do with the full sidebar.
struct BrowserSpaceMenuButton: View {
    let browser: BrowserStore
    let selectSpace: (UUID) -> Void
    let createSpace: (() -> Void)?

    var body: some View {
        if let shown = browser.shownSpace {
            Menu {
                ForEach(browser.availableSpaces, id: \.id) { space in
                    Toggle(
                        isOn: Binding(get: { space.id == shown.id }, set: { _ in selectSpace(space.id) })
                    ) {
                        Label(space.settings.name, systemImage: space.settings.symbol)
                    }
                }
                if let createSpace {
                    Divider()
                    Button("New Space…", systemImage: "plus", action: createSpace)
                }
            } label: {
                BrowserSpaceSymbolArtwork(
                    identity: BrowserSpaceIdentity(space: shown), size: BrowserTopBarMetrics.spaceIconSize,
                    lockSize: BrowserTopBarMetrics.spaceIconSize / 2)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(OdeChromeButtonStyle())
            .fixedSize()
            .help(Text("Space: \(shown.settings.name)"))
            .accessibilityLabel(Text("Space: \(shown.settings.name)"))
        }
    }
}
