import SwiftUI
import WidgetKit

struct OdeSearchWidgetView: View {
    // MARK: - Variables

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.semibold))
                }
                .containerBackground(for: .widget) {}
            } else {
                VStack(alignment: .leading) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(renderingMode == .fullColor ? OdeBrandPalette.butter : .primary)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Search")
                        .font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(
                    renderingMode == .fullColor
                        ? (colorScheme == .dark ? OdeBrandPalette.paper : OdeBrandPalette.ink) : .primary
                )
                .containerBackground(for: .widget) {
                    if renderingMode == .fullColor {
                        colorScheme == .dark ? OdeBrandPalette.ink : OdeBrandPalette.paper
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Search in Ode"))
        .accessibilityAddTraits(.isLink)
    }
}
