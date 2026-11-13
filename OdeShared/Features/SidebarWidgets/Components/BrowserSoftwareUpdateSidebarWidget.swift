import SwiftUI

struct BrowserSoftwareUpdateSidebarWidget: View {
    // MARK: - Variables

    let instance: BrowserSidebarWidgetInstance
    let update: BrowserSoftwareUpdateWidgetSnapshot
    @Binding var isExpanded: Bool
    let allowsCollapsing: Bool
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void

    @Environment(\.browserSoftwareUpdateDetails) private var showDetails
    @Environment(\.browserAutomaticUpdates) private var automaticUpdates

    private var canHide: Bool {
        instance.availableActions.contains(.hideSoftwareUpdate)
    }

    private var buttonActions: [BrowserSidebarWidgetAction] {
        instance.availableActions.filter { $0.cardButton != nil }
            .sorted { ($0.cardButton?.priority ?? 0) < ($1.cardButton?.priority ?? 0) }
    }

    /// Failures and required decisions stay visible; release information belongs in Details.
    private var showsOperationalMessage: Bool {
        update.phase == .failed || update.phase == .permission || update.phase == .unavailable
            || update.phase == .installing
            || (update.isAutomaticUpdate && update.phase == .readyToInstall && automaticUpdates?.wrappedValue == false)
    }

    private var hasDetails: Bool {
        if let releaseNotes = update.releaseNotes, !releaseNotes.isEmpty { return true }
        return update.informationURL != nil || update.version != nil || update.build != nil
            || !update.highlights.isEmpty || update.isSecurityOnly
    }

    private var statusLabel: LocalizedStringResource {
        (update.isInformationOnly ? update.phase.informationOnlyStatusLabel : nil) ?? update.phase.statusLabel
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedCard
            } else {
                disclosureButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ode software update")
    }

    // MARK: - Actions - Disclosure

    private var disclosureButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: OdeSpacing.extraSmall) {
                Text("Ode Update Available")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                fixtureBadge
            }
            .padding(.horizontal, OdeSpacing.small)
            .padding(.vertical, OdeSpacing.extraSmall)
            .frame(maxWidth: .infinity, minHeight: OdeLayout.sidebarRowHeight)
        }
        .buttonStyle(OdeChromeButtonStyle(controlSize: nil))
        .accessibilityValue(isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
        .accessibilityIdentifier("software-update-disclosure")
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.contentSpacing) {
            HStack(alignment: .top, spacing: OdeSpacing.extraSmall) {
                if allowsCollapsing {
                    disclosureButton
                } else {
                    HStack(spacing: OdeSpacing.extraSmall) {
                        Text(update.phase.title).font(.subheadline.weight(.semibold))
                        fixtureBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                hideButton
            }

            if let automaticUpdates {
                Divider()
                Toggle(String(localized: "Automatic Updates"), isOn: automaticUpdates)
                    .toggleStyle(.automatic)
                    .font(.subheadline)
                    .help(
                        "Download future updates automatically. Updates already prepared can still install when you quit. Update checks stay unchanged."
                    )
                    .accessibilityIdentifier("sidebar-automatic-updates")
            }

            progressZone
            actions

            if hasDetails, let showDetails {
                Button(String(localized: "Details")) { showDetails() }
                    .buttonStyle(OdeChromeButtonStyle(controlSize: nil))
                    .font(OdeTypography.metadata.weight(.medium))
                    .foregroundStyle(OdeBrandTheme.accent)
                    .accessibilityLabel("Review update details")
            }
            reminder
        }
    }

    @ViewBuilder
    private var fixtureBadge: some View {
        if update.isFixture {
            Text("TEST")
                .font(OdeTypography.badge)
                .padding(.horizontal, OdeSpacing.extraSmall)
                .padding(.vertical, BrowserSidebarWidgetDeckStyle.badgeVerticalPadding)
                .background(OdeColor.warningFill, in: .capsule)
                .accessibilityLabel("Test fixture")
        }
    }

    // MARK: - Actions - Status

    @ViewBuilder
    private var progressZone: some View {
        if let progress = update.progress, update.phase.isTransferring {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(OdeBrandTheme.accent)
                .accessibilityLabel(Text(statusLabel))
        } else if update.phase.isWorking {
            HStack(spacing: OdeSpacing.small) {
                ProgressView().controlSize(.small)
                Text(statusLabel)
                    .font(OdeTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(statusLabel))
        }
        if let message = update.message, showsOperationalMessage {
            Text(verbatim: message)
                .font(OdeTypography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions - Update

    @ViewBuilder
    private var actions: some View {
        if !buttonActions.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.small) { actionButtons }
                VStack(spacing: OdeSpacing.small) { actionButtons }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        let primary = buttonActions.first { $0.cardButton?.isProminent == true }
        ForEach(buttonActions, id: \.self) { action in
            if let button = action.cardButton {
                actionButton(action, button, emphasis: action == primary ? .prominent : .quiet)
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        _ action: BrowserSidebarWidgetAction,
        _ button: BrowserSidebarWidgetAction.CardButton,
        emphasis: BrowserSidebarWidgetActionEmphasis
    ) -> some View {
        // Only the model's genuinely ready action can offer a restart.
        let title: LocalizedStringResource = action == .installAndRelaunch ? "Restart and Update" : button.title
        let label = Label {
            Text(title)
        } icon: {
            Image(systemName: button.symbol)
        }
        if button.opensReleasePage {
            if let informationURL = update.informationURL {
                Link(destination: informationURL) { label }
                    .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
            }
        } else {
            Button {
                perform(action, instance.id)
            } label: {
                label
            }
            .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
            .accessibilityLabel(Text(action == .installAndRelaunch ? title : button.accessibilityLabel ?? title))
            .help(Text(button.accessibilityLabel ?? title))
        }
    }

    @ViewBuilder
    private var hideButton: some View {
        if canHide {
            Button {
                perform(.hideSoftwareUpdate, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing))
            .accessibilityLabel("Hide update")
            .help("Hide until you check for updates")
        }
    }

    @ViewBuilder
    private var reminder: some View {
        if instance.availableActions.contains(.remindUpdateTomorrow) {
            Button("Remind me tomorrow") { perform(.remindUpdateTomorrow, instance.id) }
                .buttonStyle(.plain)
                .font(OdeTypography.metadata.weight(.medium))
                .foregroundStyle(.secondary)
                .help("Hide this update for a day")
        }
    }
}

extension EnvironmentValues {
    /// Opens the existing full release notes only after an explicit Details action.
    @Entry var browserSoftwareUpdateDetails: BrowserSoftwareUpdateDetailsAction? = nil
    /// The shell supplies actual updater preferences; isolated fixtures supply local test state instead.
    @Entry var browserAutomaticUpdates: Binding<Bool>? = nil
}
