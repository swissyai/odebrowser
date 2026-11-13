import SwiftUI

/// The single row inside the address field: leading glyph or site control, the
/// address itself, the clear control, and the trailing site control.
struct BrowserSidebarAddressFieldContent<
    LeadingAccessory: View,
    TrailingAccessory: View
>: View {
    // MARK: - Variables

    let configuration: BrowserSidebarAddressFieldConfiguration
    private let leadingAccessory: LeadingAccessory
    private let trailingAccessory: TrailingAccessory

    // MARK: - Initializers

    init(
        configuration: BrowserSidebarAddressFieldConfiguration,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory
    ) {
        self.configuration = configuration
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    // MARK: - Actions - Presentation

    var body: some View {
        HStack(spacing: configuration.metrics.contentSpacing) {
            leadingControl

            BrowserAddressContent(
                text: configuration.text,
                isEditing: configuration.isEditing,
                showsSummaryRoute: configuration.showsSummaryRoute,
                focusRequest: configuration.focusRequest,
                activate: configuration.activate,
                copyAddress: configuration.copyAddress,
                editorAccessibilityLabel: configuration
                    .addressAccessibilityLabel,
                editorAccessibilityIdentifier: configuration
                    .addressAccessibilityIdentifier,
                summaryAccessibilityIdentifier: configuration
                    .addressDisplayAccessibilityIdentifier,
                prompt: configuration.prompt,
                submit: configuration.submit
            )

            if configuration.showsClearControl {
                BrowserSidebarAddressClearButton(
                    text: configuration.text,
                    font: configuration.metrics.clearControlFont
                )
            }

            if configuration.showsTrailingAccessory {
                trailingAccessory
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if configuration.showsLeadingAccessory {
            leadingAccessory
        } else if configuration.showsPlaceholderGlyph {
            BrowserSidebarAddressPlaceholderGlyph(
                isSecure: configuration.isSecure,
                metrics: configuration.metrics
            )
        }
    }
}
