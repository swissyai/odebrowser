import SwiftUI

struct BrowserAboutSettingsPane: View {
    // MARK: - Static Variables

    static let startsWhatsNewExpanded = false
    /// The app icon's side, which leads the pane.
    static let iconSide: CGFloat = 72
    private static let basedOn: LocalizedStringResource =
        "Ode is based on Crest by Paul Davis and its contributors."
    private static let unaffiliated: LocalizedStringResource =
        "Ode isn’t affiliated with or endorsed by Crest or Paul Davis."

    // MARK: - Variables

    let buildInformation: BrowserAboutBuildInformation
    let releaseNotes: [BrowserAboutReleaseNote]

    @State private var showsWhatsNew: Bool

    // MARK: - Initializers

    init(
        buildInformation: BrowserAboutBuildInformation = .current,
        releaseNotes: [BrowserAboutReleaseNote] =
            BrowserAboutReleaseNotes.bundled.currentHighlights()
    ) {
        self.buildInformation = buildInformation
        self.releaseNotes = releaseNotes
        _showsWhatsNew = State(initialValue: Self.startsWhatsNewExpanded)
    }

    var body: some View {
        BrowserSettingsPane(.about) {
            Section {
                appIdentity
            }

            #if os(macOS)
                BrowserSoftwareUpdateSettingsSection()
            #endif

            BrowserPlatformCrashReportsSettingsSection()

            if !releaseNotes.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsWhatsNew) {
                        VStack(
                            alignment: .leading,
                            spacing: OdeSpacing.medium
                        ) {
                            ForEach(releaseNotes) { releaseNote in
                                BrowserAboutReleaseNoteRow(
                                    releaseNote: releaseNote
                                )
                            }
                        }
                        .padding(.vertical, OdeSpacing.small)
                    } label: {
                        Text("What's New in Ode \(buildInformation.version)")
                            .font(.body.weight(.medium))
                    }
                    .disclosureGroupStyle(
                        BrowserAboutWhatsNewDisclosureStyle()
                    )
                }
            }

            Section {
                BrowserFeedbackButton(
                    title: "Share Feedback",
                    systemImage: "bubble.left"
                )
                .accessibilityIdentifier("about-feedback-link")
                BrowserFeedbackButton(
                    title: "Report an Issue",
                    systemImage: "exclamationmark.bubble",
                    topic: String(localized: "Issue")
                )
                .accessibilityIdentifier("about-issues-link")
            } header: {
                Text("Feedback and support")
            }

            credits
        }
    }

    // MARK: - Actions - Presentation

    /// Where Ode comes from, as Crest's trademark policy asks a fork to say
    /// it: less prominently than Ode's own name, beside a plain statement
    /// that the two aren't affiliated, with the licenses that cover it.
    private var credits: some View {
        Section {
            DisclosureGroup("Credits and Licenses") {
                VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                    Text(Self.basedOn)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.unaffiliated)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                BrowserAboutLink(
                    title: "Mozilla Public License 2.0",
                    systemImage: "doc.text",
                    destination: BrowserAboutLinks.mozillaPublicLicense,
                    identifier: "about-license-link"
                )
                BrowserAboutLink(
                    title: "Chromium license",
                    systemImage: "doc.text",
                    destination: BrowserAboutLinks.chromiumLicense,
                    identifier: "about-chromium-license-link"
                )
                BrowserAboutLink(
                    title: "WebKit license",
                    systemImage: "doc.text",
                    destination: BrowserAboutLinks.webKitLicense,
                    identifier: "about-webkit-license-link"
                )
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: OdeSpacing.large) {
            BrowserPlatformCurrentAppIcon()
                .frame(width: Self.iconSide, height: Self.iconSide)
                .clipShape(.rect(cornerRadius: Self.iconSide * OdeStartPageMarkMetrics.cornerRadiusRatio))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                Text(ProductIdentity.name)
                    .font(OdeTypography.displayPage)
                    .accessibilityAddTraits(.isHeader)
                // Selectable text is an AppKit view: a label with no value recurses when assistive apps read it.
                Text("Version \(buildInformation.version) (\(buildInformation.build))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Version")
                    .accessibilityValue(
                        Text(
                            "\(buildInformation.version), build \(buildInformation.build), bundle identifier: \(buildInformation.bundleIdentifier)"
                        )
                    )
                    .help(buildInformation.bundleIdentifier)
                BrowserPlatformAboutStatus()
                    .padding(.top, OdeSpacing.extraSmall)
            }
        }
        .padding(.vertical, OdeSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct BrowserAboutWhatsNewDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: OdeSpacing.small) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(
                            .degrees(configuration.isExpanded ? 90 : 0)
                        )
                        .accessibilityHidden(true)

                    configuration.label

                    Spacer(minLength: OdeSpacing.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about-whats-new-disclosure")
            .accessibilityValue(
                configuration.isExpanded ? "Expanded" : "Collapsed"
            )
            .accessibilityHint(
                configuration.isExpanded
                    ? "Hides recent changes"
                    : "Shows recent changes"
            )

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct BrowserAboutLink: View {
    let title: LocalizedStringResource
    let systemImage: String
    let destination: URL
    let identifier: String

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: OdeSpacing.medium) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: OdeSpacing.small)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct BrowserAboutReleaseNoteRow: View {
    let releaseNote: BrowserAboutReleaseNote

    var body: some View {
        let mark = BrowserAboutReleaseNoteMark.marking(releaseNote.category)
        HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
            Image(systemName: mark.symbol)
                .foregroundStyle(mark.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(releaseNote.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The glyph that marks each kind of release note in What's New.
private struct BrowserAboutReleaseNoteMark: Sendable {
    // MARK: - Static Variables

    static let new = BrowserAboutReleaseNoteMark(category: .new, symbol: "sparkles", color: OdeBrandPalette.sky)
    static let improved = BrowserAboutReleaseNoteMark(
        category: .improved, symbol: "arrow.up.circle.fill", color: OdeBrandPalette.butter)
    static let fixed = BrowserAboutReleaseNoteMark(
        category: .fixed, symbol: "checkmark.circle.fill", color: OdeBrandPalette.sage)
    static let `internal` = BrowserAboutReleaseNoteMark(
        category: .internal, symbol: "wrench.and.screwdriver.fill", color: .secondary)

    /// A mark for every category.
    static let all: [BrowserAboutReleaseNoteMark] = [new, improved, fixed, `internal`]

    // MARK: - Variables

    let category: BrowserAboutReleaseNoteCategory
    let symbol: String
    let color: Color

    // MARK: - Actions - Lookup

    static func marking(_ category: BrowserAboutReleaseNoteCategory) -> BrowserAboutReleaseNoteMark {
        all.first { $0.category == category } ?? .internal
    }
}
